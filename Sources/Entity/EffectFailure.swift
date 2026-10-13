/// Why an effect did not produce a frame. Closed so that every consumer
/// enumerates it: `GPURenderDataSource` maps raw `RawGPUError` codes onto
/// these, `EffectHealthPolicy` counts them, and the pipeline passes the input
/// frame through on any of them. Adding a case is the only way to add a cause.
public enum EffectFailure: Error, Sendable, Hashable {
    case compileFailed
    case timeout
    case pageFault
    case accessRevoked
    case outOfMemory
    case invalidResource
    /// A failure of the runtime itself rather than of the effect (no GPU context,
    /// a pass that could not be committed), never something the effect's author caused.
    case internalError
    /// A raw code no mapping claims; kept so it is visible in the logs.
    case unknown(code: Int)
}
