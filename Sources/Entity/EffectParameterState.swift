/// What the parameter panel shows for one knob of the chosen effect: the declaration and the value
/// it currently has. Kept as a pair so the control and the value it edits cannot come from two
/// different snapshots.
public struct EffectParameterState: Sendable, Hashable {
    public let spec: EffectParameterSpec
    public let value: EffectParameterValue

    public init(spec: EffectParameterSpec, value: EffectParameterValue) {
        self.spec = spec
        self.value = value
    }
}
