import Domain

/// The runtime with no effect loaded: nothing prepares and nothing applies, so
/// the pipeline passes every frame through unchanged. Registered as the host's
/// live value until the real runtime lands in this module (#19), so a later
/// PR merged ahead of it never leaves the pipeline without a runtime (epic
/// #14, D18). Both answers are `.internalError` — the failure that means "the
/// runtime, not the effect" — so nothing upstream mistakes this for an effect
/// that compiled.
public struct PassthroughEffectRuntimeRepository: EffectRuntimeRepository, Sendable {
    public init() {}

    public func prepare(_ effect: EffectSource) async -> Result<Void, EffectFailure> {
        .failure(.internalError)
    }

    public func apply(input: FrameRef, output: FrameRef, frameContext: FrameContext) async -> Result<Void, EffectFailure> {
        .failure(.internalError)
    }
}
