import Domain

/// The one frame the effect runtime is working on (the in-flight cap is one).
/// The pipeline owns both leases for the pass's whole life: `input` until the
/// runtime is done reading it, `output` until the sink has seen it. `number`
/// tells this pass's completion apart from that of a pass `stop` abandoned.
struct EffectPass {
    let number: Int
    let input: FrameRef
    let output: FrameRef
    /// The work carrying `apply`; `stop` cancels it.
    let work: any WorkHandle
}
