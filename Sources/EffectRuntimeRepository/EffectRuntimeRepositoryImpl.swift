import Dependencies
import Domain

/// The effect runtime: compiles an effect once per process through
/// `ShaderCompiler`, decides which effect `apply` runs, and runs it through
/// `GPURenderer`.
///
/// **Executor-confined, like `GPURenderDataSource`.** The cache, the selection and
/// the session live on `FrameExecutor`, so there is no lock and no actor: each
/// call hops there to decide, does its slow part (the compile, the GPU pass) off
/// it, and hops back to settle.
///
/// **The cache** is in-process and keyed by `(source, compile options)` — hashed,
/// then compared, so two sources never share a library — and never by the name,
/// so one source compiles once whatever it is called. Only a compile that
/// succeeded is kept: preparing a broken source again compiles it again. Device
/// id, OS version and a cache on disk are MVP-B (epic #14, D14).
///
/// **Newest wins.** Every `prepare` takes the next ticket, and `apply` runs the
/// effect of the newest one. A compile that finishes after a newer `prepare`
/// still answers its caller with its real outcome, and a success still fills the
/// cache, but it never becomes the effect `apply` runs. A cache hit settles at
/// once, so it overtakes a compile still running. Two `prepare`s of one source
/// while its compile runs compile it twice: compiles are rare (one per effect
/// change), so they are not joined.
///
/// **The bundled default.** Until something is prepared, the first `apply`
/// prepares `BundledEffects.defaultEffect` itself, so the pipeline runs the
/// bundled effect without knowing it exists (MVP-A has no effect menu).
///
/// **Waiting, not failing.** An `apply` that finds the newest compile still
/// running waits for it to settle and then runs it, or answers its failure —
/// one slow pass rather than frames counted as failures. A source that does not
/// compile is final for the frames that follow: they answer `.compileFailed` at
/// once, without compiling again, until a newer `prepare`. A compile that failed
/// for want of a GPU context (`ShaderDiagnostics.cause == .environment`) is not
/// the effect's fault: it answers `.internalError`, as the renderer does for the
/// same cause, and the next `apply` compiles that effect again.
///
/// **Uniforms** are built on the executor when the frame arrives
/// (`EffectUniforms.pass`): `time` from the `EffectSession`, the caller's
/// `frameIndex`, the output's size, seed 0.
///
/// Cancellation cuts nothing short (the port's contract): neither call observes
/// it, nor do the compiler and the renderer, so a cancelled caller still
/// receives the real outcome.
public final class EffectRuntimeRepositoryImpl: @unchecked Sendable {
    @Dependency(\.shaderCompiler) private var compiler
    @Dependency(\.gpuRenderer) private var renderer
    @Dependency(\.bundledEffects) private var bundledEffects
    @Dependency(\.frameExecutor) private var executor
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    // Executor-confined.
    private var cache: [CompileKey: any LibraryHandle] = [:]
    private var selection = Selection.nothing
    /// The ticket of the newest `prepare`; a compile settles the selection only under it.
    private var newestTicket = 0
    /// `apply`s waiting for the newest compile to settle, resumed in arrival order.
    private var waiting: [@Sendable (Result<any LibraryHandle, EffectFailure>) -> Void] = []
    private var session: EffectSession?

    public init() {}
}

extension EffectRuntimeRepositoryImpl: EffectRuntimeRepository {
    public func prepare(_ effect: EffectSource) async -> Result<Void, EffectFailure> {
        switch await onExecutor({ [self] in begin(effect) }) {
        case .settled(let result): result
        case .compile(let ticket): await compile(effect, ticket: ticket)
        }
    }

    public func apply(input: FrameRef, output: FrameRef, frameContext: FrameContext) async -> Result<Void, EffectFailure> {
        let library: Result<any LibraryHandle, EffectFailure>
        let uniforms: EffectUniforms
        switch await admit(frameContext, output: output.descriptor) {
        case .ready(let admitted, let passUniforms):
            (library, uniforms) = (admitted, passUniforms)
        case .compile(let effect, let ticket, let passUniforms):
            _ = await compile(effect, ticket: ticket)
            (library, uniforms) = (await selected(), passUniforms)
        }
        switch library {
        case .success(let kernel):
            return await renderer.render(library: kernel, input: input.token, output: output.token, uniforms: uniforms).map { _ in () }
        case .failure(let failure):
            return .failure(failure)
        }
    }
}

// MARK: - Executor-confined steps

extension EffectRuntimeRepositoryImpl {
    /// What a `prepare` does after its first hop.
    private enum Begin: Sendable {
        case settled(Result<Void, EffectFailure>)
        case compile(ticket: Int)
    }

    /// What an `apply` does after its first hop.
    private enum Admission: Sendable {
        /// The selection has settled (at once, or after waiting for the newest compile).
        case ready(Result<any LibraryHandle, EffectFailure>, EffectUniforms)
        /// Nothing is ready but there is an effect to compile (the bundled one while nothing
        /// was prepared, or the one whose compile found no GPU context): this `apply`
        /// compiles it, then reads the selection.
        case compile(EffectSource, ticket: Int, EffectUniforms)
    }

    /// Takes the next ticket: a cache hit is selected at once, anything else starts
    /// a compile that only this ticket may settle.
    private func begin(_ effect: EffectSource) -> Begin {
        newestTicket += 1
        guard let library = cache[CompileKey(effect)] else {
            selection = .compiling
            return .compile(ticket: newestTicket)
        }
        select(.ready(library))
        return .settled(.success(()))
    }

    /// The compile itself, off the executor, then its outcome settled on it.
    private func compile(_ effect: EffectSource, ticket: Int) async -> Result<Void, EffectFailure> {
        let outcome = await compiler.compile(effect)
        return await onExecutor { [self] in settle(effect, ticket: ticket, outcome: outcome) }
    }

    /// Caches a success whatever its ticket; selects the outcome only when no newer
    /// `prepare` has come since. The caller hears its own compile's outcome either way.
    private func settle(
        _ effect: EffectSource, ticket: Int, outcome: Result<any LibraryHandle, ShaderDiagnostics>
    ) -> Result<Void, EffectFailure> {
        let isNewest = ticket == newestTicket
        switch outcome {
        case .success(let library):
            cache[CompileKey(effect)] = library
            developerLog.record(.effect, "effect '\(effect.name)' compiled\(isNewest ? "" : ", but a newer one was prepared since")")
            if isNewest { select(.ready(library)) }
            return .success(())
        case .failure(let diagnostics):
            errorLog.record(.effect, "effect '\(effect.name)' did not compile: \(diagnostics.message)")
            switch diagnostics.cause {
            case .source:
                if isNewest { select(.failed) }
                return .failure(.compileFailed)
            case .environment:
                if isNewest { select(.retry(effect)) }
                return .failure(.internalError)
            }
        }
    }

    /// Sets the selection; once it has settled, every waiting `apply` is resumed with it.
    private func select(_ next: Selection) {
        selection = next
        guard let settled = next.settled else { return }
        let resumed = waiting
        waiting = []
        for resume in resumed { resume(settled) }
    }

    /// The first hop of an `apply`: the pass's uniforms, and the library it runs
    /// once the selection has settled.
    private func admit(_ context: FrameContext, output: SurfaceDescriptor) async -> Admission {
        await withCheckedContinuation { continuation in
            executor.run { [self] in
                let current = EffectSession.of(context, after: session)
                session = current
                let uniforms = EffectUniforms.pass(context, in: current, output: output)
                if let effect = compilable, case .compile(let ticket) = begin(effect) {
                    return continuation.resume(returning: .compile(effect, ticket: ticket, uniforms))
                }
                whenSettled { continuation.resume(returning: .ready($0, uniforms)) }
            }
        }
    }

    /// The effect an `apply` compiles itself: the bundled one while nothing has been
    /// prepared, or the one whose compile found no GPU context. Executor-confined.
    private var compilable: EffectSource? {
        switch selection {
        case .nothing: bundledEffects.defaultEffect
        case .retry(let effect): effect
        case .compiling, .ready, .failed: nil
        }
    }

    /// The selection once it has settled: at once, or when the newest compile does.
    private func selected() async -> Result<any LibraryHandle, EffectFailure> {
        await withCheckedContinuation { continuation in
            executor.run { [self] in whenSettled { continuation.resume(returning: $0) } }
        }
    }

    private func whenSettled(_ resume: @escaping @Sendable (Result<any LibraryHandle, EffectFailure>) -> Void) {
        guard let settled = selection.settled else { return waiting.append(resume) }
        resume(settled)
    }

    private func onExecutor<Value: Sendable>(_ body: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            executor.run { continuation.resume(returning: body()) }
        }
    }
}

/// What the cache is keyed by: the source and how it is compiled, never the name.
private struct CompileKey: Hashable {
    let source: String
    let options: ShaderCompileOptions

    init(_ effect: EffectSource) {
        source = effect.source
        options = effect.options
    }
}

/// The effect `apply` runs, as the newest `prepare` left it. It never returns to
/// `nothing`.
private enum Selection {
    /// No `prepare` yet: the next `apply` prepares the bundled effect.
    case nothing
    /// The newest `prepare`'s compile is running.
    case compiling
    case ready(any LibraryHandle)
    /// The newest `prepare`'s source does not compile: final until a newer `prepare`.
    case failed
    /// The newest `prepare`'s compile found no GPU context, which is not the effect's
    /// fault: not final. The next `apply` compiles this effect again.
    case retry(EffectSource)

    /// What an `apply` gets from it, or `nil` while there is nothing to run yet.
    var settled: Result<any LibraryHandle, EffectFailure>? {
        switch self {
        case .ready(let library): .success(library)
        case .failed: .failure(.compileFailed)
        case .retry: .failure(.internalError)
        case .nothing, .compiling: nil
        }
    }
}
