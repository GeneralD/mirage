import Dependencies
import Domain

/// The effect runtime: compiles an effect through `ShaderCompiler`, remembers it in
/// `EffectRuntimeState`, and runs it through `GPURenderer`. This layer only
/// orchestrates — it holds no state and no executor — and the rules live below it:
/// the cache, newest wins and the session clock in `EffectRuntimeStateDataSource`,
/// the compile in `ShaderCompilationDataSource`, the pass in `GPURenderDataSource`.
///
/// **`prepare`** asks the state to `begin` (a cache hit settles at once), compiles on
/// a miss, and settles the outcome under the ticket it was given. A compile that
/// finishes after a newer `prepare` still answers its own caller with its real
/// outcome; the state decides that it does not become the effect `apply` runs.
///
/// **`apply`** is admitted by the state, which also builds the pass's uniforms
/// (`EffectUniforms.pass`). Until something is prepared, the first `apply` prepares
/// `BundledEffects.defaultEffect` itself, so the pipeline runs the bundled effect
/// without knowing it exists (MVP-A has no effect menu); an `apply` that meets a
/// compile still running waits for it rather than counting a failure. A failure
/// is one the effect's author caused (`.compileFailed`, final until a newer
/// `prepare`) or the runtime's (`.internalError`: no GPU context, tried again by
/// the next `apply`).
///
/// An `apply` that compiles an effect itself starts that compile on the `WorkRunner`
/// and waits for the *selection*, not for its own compile: the compile settles the
/// state whenever it ends (cache, log), and the selection answers as soon as the
/// newest effect has settled, which a newer `prepare` may do first. The frame does
/// not wait behind a stale compile, so it does not hold the pipeline's in-flight cap
/// for it. The compile holds no lease, so the leases still stay the caller's until
/// `apply` returns.
///
/// Cancellation cuts nothing short (the port's contract): neither call observes it,
/// nor do the state, the compiler and the renderer, so a cancelled caller still
/// receives the real outcome.
public struct EffectRuntimeRepositoryImpl: Sendable {
    @Dependency(\.effectRuntimeState) private var state
    @Dependency(\.shaderCompiler) private var compiler
    @Dependency(\.gpuRenderer) private var renderer
    @Dependency(\.bundledEffects) private var bundledEffects
    @Dependency(\.workRunner) private var workRunner
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension EffectRuntimeRepositoryImpl: EffectRuntimeRepository {
    public func prepare(_ effect: EffectSource) async -> Result<Void, EffectFailure> {
        switch await state.begin(effect) {
        case .cached: .success(())
        case .compile(let ticket): await compile(effect, under: ticket)
        }
    }

    public func apply(input: FrameRef, output: FrameRef, frameContext: FrameContext) async -> Result<Void, EffectFailure> {
        let bundled = bundledEffects
        let library: Result<any LibraryHandle, EffectFailure>
        let uniforms: EffectUniforms
        switch await state.admit(frameContext, output: output.descriptor, fallback: { bundled.defaultEffect }) {
        case .ready(let admitted, let passUniforms):
            (library, uniforms) = (admitted, passUniforms)
        case .compile(let effect, let ticket, let passUniforms):
            // Started, not awaited, and not cancellable: the compile settles the state
            // when it ends, and `selected()` answers when the newest effect has.
            _ = workRunner.run { [self] in _ = await compile(effect, under: ticket) }
            (library, uniforms) = (await state.selected(), passUniforms)
        }
        switch library {
        case .success(let kernel):
            return await renderer.render(library: kernel, input: input.token, output: output.token, uniforms: uniforms).map { _ in () }
        case .failure(let failure):
            return .failure(failure)
        }
    }
}

extension EffectRuntimeRepositoryImpl {
    /// One compile, then its outcome settled under `ticket`. The caller hears its own
    /// compile's outcome whether or not a newer `prepare` has come since.
    private func compile(_ effect: EffectSource, under ticket: EffectTicket) async -> Result<Void, EffectFailure> {
        let outcome = await compiler.compile(effect)
        switch await state.settle(effect, ticket: ticket, outcome: outcome) {
        case .compiled(let selected):
            developerLog.record(.effect, "effect '\(effect.name)' compiled\(selected ? "" : ", but a newer one was prepared since")")
            return .success(())
        case .failed(let failure):
            if case .failure(let diagnostics) = outcome {
                errorLog.record(.effect, "effect '\(effect.name)' did not compile: \(diagnostics.message)")
            }
            return .failure(failure)
        }
    }
}
