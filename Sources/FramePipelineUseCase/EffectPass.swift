import Domain

/// The one frame the effect runtime is working on (the in-flight cap is one), with
/// both of its leases. Only the runtime's answer ends a pass — cancellation cuts no
/// GPU work short — so a pass `stop` gives up on stays here, holding the cap and its
/// leases, until that answer arrives.
struct EffectPass {
    let input: FrameRef
    let output: FrameRef
    /// The stop count the pass's run started under, as that run's `start` read it —
    /// never a value read by the tick. A `stop` since then has abandoned the pass: its
    /// answer only ends the two leases.
    let epoch: Int
}
