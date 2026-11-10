/// The menu-bar controls' state: whether the effect is bypassed, and the frame rate shown as a readout.
public struct ControlsState: Sendable, Hashable {
    public let isBypassed: Bool
    public let framesPerSecond: Int

    public init(isBypassed: Bool = false, framesPerSecond: Int = 0) {
        self.isBypassed = isBypassed
        self.framesPerSecond = framesPerSecond
    }
}

/// A step through the effects: to the next one, or to the previous one.
public enum EffectStep: Sendable, Hashable, CaseIterable {
    case next
    case previous
}
