import Dependencies

/// The effect runtime as the pipeline sees it: make an effect ready (compile,
/// cache the handle) and apply it to one frame. Both run off the frame
/// executor (`async`) and neither throws — every outcome is an `EffectFailure`
/// the pipeline turns into a pass-through and `EffectHealthPolicy` counts.
/// Cancelling the caller cuts neither call short: a compile or a GPU pass that
/// has started runs to its end and the call answers with its real outcome, so
/// the caller holds the leases it handed in until `apply` returns.
/// The live value is `EffectRuntimeRepositoryImpl`: an in-process compile
/// cache, newest-wins, and the bundled effect while nothing has been prepared.
public protocol EffectRuntimeRepository: Sendable {
    /// Compiles `effect` (or finds it in the cache) so `apply` can run it.
    /// Never on the main thread; a slow compile overtaken by a newer `prepare`
    /// loses ("newest wins").
    func prepare(_ effect: EffectSource) async -> Result<Void, EffectFailure>
    /// Runs the prepared effect from `input` into `output`. Both leases stay
    /// the caller's; the runtime only borrows the surfaces for the pass.
    func apply(input: FrameRef, output: FrameRef, frameContext: FrameContext) async -> Result<Void, EffectFailure>
}

public enum EffectRuntimeRepositoryKey: TestDependencyKey {
    public static let testValue: any EffectRuntimeRepository = UnimplementedEffectRuntimeRepository()
}

extension DependencyValues {
    public var effectRuntimeRepository: any EffectRuntimeRepository {
        get { self[EffectRuntimeRepositoryKey.self] }
        set { self[EffectRuntimeRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedEffectRuntimeRepository: EffectRuntimeRepository {
    func prepare(_ effect: EffectSource) async -> Result<Void, EffectFailure> {
        reportIssue("EffectRuntimeRepository.prepare not implemented")
        return .failure(.internalError)
    }

    func apply(input: FrameRef, output: FrameRef, frameContext: FrameContext) async -> Result<Void, EffectFailure> {
        reportIssue("EffectRuntimeRepository.apply not implemented")
        return .failure(.internalError)
    }
}
