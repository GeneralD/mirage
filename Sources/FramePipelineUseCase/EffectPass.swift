import Domain

/// The one frame the effect runtime is working on (the in-flight cap is one).
/// The pipeline owns both leases for the pass's whole life: `input` until the
/// runtime is done reading it, `output` until the sink has seen it. Only the
/// runtime's answer ends a pass — cancellation cuts no GPU work short — so a pass
/// `stop` gives up on stays here, abandoned, until that answer arrives.
struct EffectPass {
    let input: FrameRef
    let output: FrameRef
    /// `stop` came while the pass ran: its answer only ends the two leases.
    let isAbandoned: Bool

    /// The same pass, given up on by `stop`.
    var abandoned: Self { Self(input: input, output: output, isAbandoned: true) }
}
