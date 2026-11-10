import Dependencies

/// The effect runtime as the pipeline sees it: make an effect ready (compile,
/// cache the handle) and apply it to one frame. Both run off the frame
/// executor (`async`) and neither throws — every outcome is an `EffectFailure`
/// the pipeline turns into a pass-through and `EffectHealthPolicy` counts.
/// Cancelling the caller cuts neither call short: a compile or a GPU pass that
/// has started runs to its end and the call answers with its real outcome, so
/// the caller holds the leases it handed in until `apply` returns.
/// The live value is `EffectRuntimeRepositoryImpl`, which only orchestrates the
/// compile and the render; the in-process compile cache, newest-wins and the
/// bundled effect while nothing has been prepared live in `EffectRuntimeState`.
public protocol EffectRuntimeRepository: Sendable {
    /// Compiles `effect` (or finds it in the cache) so `apply` can run it, with `parameters`
    /// as the block it runs with from its first pass: the selection and its initial block are
    /// handed over in one step, so no pass runs the new effect with the old one's block. The
    /// block is the one packed for `effect`'s layout (`EffectParameterBlock.none` for an effect
    /// without parameters). Never on the main thread; a slow compile overtaken by a newer
    /// `prepare` loses ("newest wins").
    func prepare(_ effect: EffectSource, parameters: EffectParameterBlock) async -> Result<Void, EffectFailure>
    /// Replaces the block `source` runs with, packed for its layout. It prepares and compiles
    /// nothing, and returns as soon as the write is queued, without waiting for the frame
    /// executor, so a slider can call it at its own rate. A write for any effect but the one
    /// the newest `prepare` was given is dropped, and so is one that reaches the executor before
    /// that `prepare` does: a caller that must not lose a write sends it after `prepare` has
    /// returned. A write lands in the executor's order, ahead of every pass admitted after it; a
    /// pass `apply` has already admitted keeps the block it was given.
    func setParameters(_ block: EffectParameterBlock, of source: EffectSource)
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
    func prepare(_ effect: EffectSource, parameters: EffectParameterBlock) async -> Result<Void, EffectFailure> {
        reportIssue("EffectRuntimeRepository.prepare not implemented")
        return .failure(.internalError)
    }

    func setParameters(_ block: EffectParameterBlock, of source: EffectSource) {
        reportIssue("EffectRuntimeRepository.setParameters not implemented")
    }

    func apply(input: FrameRef, output: FrameRef, frameContext: FrameContext) async -> Result<Void, EffectFailure> {
        reportIssue("EffectRuntimeRepository.apply not implemented")
        return .failure(.internalError)
    }
}
