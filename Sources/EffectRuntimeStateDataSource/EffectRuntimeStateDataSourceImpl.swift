import Dependencies
import Domain

/// The effect runtime's memory, confined to `FrameExecutor`: the compile cache, the
/// selection, the parameter block of the effect it selects, the ticket counter, the applies
/// waiting for the selection and the session clock. Every transition runs as one executor
/// step, so no two of them interleave and there is no lock and no actor (as in
/// `GPURenderDataSource` and `SurfacePoolDataSource`). The rules are the `EffectRuntimeState` port's.
///
/// **The cache** is keyed by `(source, compile options, parameter layout)` — a `Hashable`
/// key of the three, so two sources never share a library even if their hashes collide — and
/// never by the name, so one source compiles once whatever it is called. The layout is all the
/// generated `Parameters` struct is made of (ids, field types, offsets), so a label, a default
/// or a range, which the shader never sees, does not compile an effect again. Only a compile that
/// succeeded is kept: a broken source compiles again when it is prepared again. A cache
/// on disk, and with it a device id and an OS version in the key, is deferred to Later (epic #42, D12).
///
/// **The selection** is the effect `apply` runs, as the newest `begin` left it. A cache
/// hit settles it at once, so it overtakes a compile still running, and releases the
/// applies waiting on that compile. A compile that finishes after a newer `begin`
/// still fills the cache but never takes the selection. Two `begin`s of one source
/// while its compile runs compile it twice: compiles are rare (one per effect
/// change), so they are not joined.
///
/// **Retrying.** A source that does not compile is final until a newer `begin`: the
/// selection stays failed and the frames after it answer at once. A compile that
/// found no GPU context, or whose compiler service failed (`ShaderDiagnostics.cause`
/// is `.environment`), says nothing about the source, so the selection remembers the
/// effect, and the next `admit` hands it back to be compiled again (the renderer asks
/// for its context again on the next pass for the same reason). Those retries run at
/// the camera's pace, so each settlement says where it falls in its streak of
/// consecutive failures and how long the streak was when it ended: the caller logs
/// the first and the recovery, and the rest is only counted.
///
/// **The parameter block** is the newest `begin`'s: it arrives with the effect, `setParameters`
/// replaces it, and a write addressed to any other effect is dropped (the whole `EffectSource`
/// is compared, so an edited source is another effect to write to). It is handed out only
/// together with a settled selection, read in the step that settles it: an `admit` that finds
/// the selection settled gets the block as it is, and one that waits (or an `apply` waiting in
/// `selected()`) gets the block of whatever it is released with, so a newer `begin` between the
/// admission and the release can never pair its library with the older effect's layout. A
/// retry of the newest effect keeps its block, and the bundled fallback, which declares no
/// parameters, runs with the empty one. Handing a block out copies a reference, not its bytes,
/// so a frame allocates nothing for it.
public final class EffectRuntimeStateDataSourceImpl: @unchecked Sendable {
    @Dependency(\.frameExecutor) private var executor

    // Executor-confined.
    private var cache: [CompileKey: any LibraryHandle] = [:]
    private var selection = Selection.nothing
    /// The newest `begin`'s ticket; a compile settles the selection only under it.
    private var newest = EffectTicket(number: 0)
    /// The effect of the newest `begin` (or of the fallback, or the retry, an `admit` took a
    /// ticket for), and the block that effect runs with: the only effect a write may address.
    private var newestEffect: EffectSource?
    private var parameterBlock = EffectParameterBlock.none
    /// `admit`s and `selected`s waiting for the selection to settle, resumed in arrival order.
    private var waiting: [@Sendable (EffectSelection) -> Void] = []
    private var session: EffectSession?
    /// Consecutive compiles of the newest effect that failed for the environment's
    /// reasons (no GPU context, a compiler service fault). Only a
    /// `begin` starts it over: the retries an `admit` hands back keep counting.
    private var contextFailures = 0

    public init() {}
}

extension EffectRuntimeStateDataSourceImpl: EffectRuntimeState {
    public func begin(_ effect: EffectSource, parameters block: EffectParameterBlock) async -> EffectBegin {
        await onExecutor { [self] in
            contextFailures = 0
            // Before the ticket: a cache hit selects at once, and releases waiting callers with this block.
            parameterBlock = block
            return takeTicket(for: effect)
        }
    }

    public func setParameters(_ block: EffectParameterBlock, of effect: EffectSource) {
        executor.run { [self] in
            guard effect == newestEffect else { return }
            parameterBlock = block
        }
    }

    public func settle(
        _ effect: EffectSource, ticket: EffectTicket, outcome: Result<any LibraryHandle, ShaderDiagnostics>
    ) async -> EffectSettlement {
        await onExecutor { [self] in record(outcome, of: effect, under: ticket) }
    }

    public func admit(
        _ context: FrameContext, output: SurfaceDescriptor, fallback: @escaping @Sendable () -> EffectSource
    ) async -> EffectAdmission {
        await withCheckedContinuation { continuation in
            executor.run { [self] in
                let current = EffectSession.of(context, after: session)
                session = current
                let uniforms = EffectUniforms.pass(context, in: current, output: output)
                if let effect = compilable(fallback: fallback), case .compile(let ticket) = takeTicket(for: effect) {
                    return continuation.resume(returning: .compile(effect, ticket, uniforms))
                }
                whenSettled { continuation.resume(returning: .ready($0, uniforms)) }
            }
        }
    }

    public func selected() async -> EffectSelection {
        await withCheckedContinuation { continuation in
            executor.run { [self] in whenSettled { continuation.resume(returning: $0) } }
        }
    }
}

// MARK: - Executor-confined steps

extension EffectRuntimeStateDataSourceImpl {
    /// Takes the next ticket: a cache hit is selected at once, anything else leaves the
    /// selection waiting for a compile that only this ticket may settle.
    private func takeTicket(for effect: EffectSource) -> EffectBegin {
        newest = EffectTicket(number: newest.number + 1)
        newestEffect = effect
        guard let library = cache[CompileKey(effect)] else {
            selection = .compiling
            return .compile(newest)
        }
        select(.ready(library))
        return .cached
    }

    /// Caches a success whatever its ticket; selects the outcome only when no newer
    /// `begin` has come since. The caller is told its own compile's outcome either way.
    private func record(_ outcome: Result<any LibraryHandle, ShaderDiagnostics>, of effect: EffectSource, under ticket: EffectTicket)
        -> EffectSettlement
    {
        let isNewest = ticket == newest
        switch outcome {
        case .success(let library):
            cache[CompileKey(effect)] = library
            guard isNewest else { return .compiled(selected: false) }
            let failures = contextFailures
            select(.ready(library))
            return .compiled(selected: true, afterFailures: failures)
        case .failure(let diagnostics):
            switch diagnostics.cause {
            case .source:
                if isNewest { select(.failed) }
                return .failed(.compileFailed)
            case .environment:
                guard isNewest else { return .failed(.internalError) }
                contextFailures += 1
                select(.retry(effect))
                return .failed(.internalError, attempt: contextFailures)
            }
        }
    }

    /// Sets the selection; once it has settled, every waiting caller is resumed with it
    /// and the block of the effect it selects.
    private func select(_ next: Selection) {
        selection = next
        guard let settled = next.settled else { return }
        let resumed = waiting
        waiting = []
        let released = EffectSelection(result: settled, parameters: parameterBlock)
        for resume in resumed { resume(released) }
    }

    /// The effect an `admit` compiles itself: the fallback while nothing has been
    /// prepared, or the one whose compile failed for the environment's reasons.
    private func compilable(fallback: @Sendable () -> EffectSource) -> EffectSource? {
        switch selection {
        case .nothing: fallback()
        case .retry(let effect): effect
        case .compiling, .ready, .failed: nil
        }
    }

    private func whenSettled(_ resume: @escaping @Sendable (EffectSelection) -> Void) {
        guard let settled = selection.settled else { return waiting.append(resume) }
        resume(EffectSelection(result: settled, parameters: parameterBlock))
    }

    private func onExecutor<Value: Sendable>(_ body: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            executor.run { continuation.resume(returning: body()) }
        }
    }
}

/// What the cache is keyed by: the source, how it is compiled and the layout of its parameters,
/// never the name. Built for a `begin` and a settlement, not for each frame's `admit`.
private struct CompileKey: Hashable {
    let source: String
    let options: ShaderCompileOptions
    let layout: EffectParameterLayout

    init(_ effect: EffectSource) {
        source = effect.source
        options = effect.options
        layout = EffectParameterLayout(effect.parameters)
    }
}

/// The effect `apply` runs, as the newest `begin` left it. It never returns to
/// `nothing`.
private enum Selection {
    /// No `begin` yet: the first `admit` takes the fallback to compile.
    case nothing
    /// The newest `begin`'s compile is running.
    case compiling
    case ready(any LibraryHandle)
    /// The newest `begin`'s source does not compile: final until a newer `begin`.
    case failed
    /// The newest `begin`'s compile failed for the environment's reasons (no GPU context,
    /// a compiler service fault), which are not the effect's fault: not final. The next `admit` hands this effect back to be compiled again.
    case retry(EffectSource)

    /// What a caller gets from it, or `nil` while there is nothing to run yet.
    var settled: Result<any LibraryHandle, EffectFailure>? {
        switch self {
        case .ready(let library): .success(library)
        case .failed: .failure(.compileFailed)
        case .retry: .failure(.internalError)
        case .nothing, .compiling: nil
        }
    }
}
