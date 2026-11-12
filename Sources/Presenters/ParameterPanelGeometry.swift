/// The effect parameter panel's layout at a given width (#112): the label and control columns of
/// each parameter row, and the panel's initial and minimum size. A pure value so that the numbers are
/// tested here; `ParameterPanelView` only maps them to `.frame` and stacks (`Views` is coverage-ignored
/// and holds no logic).
///
/// A width that is negative or not finite counts as no room: the columns stay at their narrowest.
public struct ParameterPanelGeometry: Sendable, Hashable {
    /// The margin on each side of the panel.
    public static let inset = 16.0
    /// The gap between a label and its control, and between two rows.
    public static let spacing = 12.0
    /// The gap between the two sliders of a vec2 parameter.
    public static let axisSpacing = 4.0
    /// The most lines a row label wraps to before it is cut off.
    public static let labelLineLimit = 2
    /// The narrowest a label column gets.
    public static let minimumLabelWidth = 80.0
    /// The widest a label column gets.
    public static let maximumLabelWidth = 160.0
    /// The share of the usable width the label column takes, before it is clamped to its bounds.
    public static let labelShare = 0.3
    /// The narrowest a control column gets.
    public static let minimumControlWidth = 120.0
    /// The width of the value shown beside a slider or a stepper.
    public static let valueWidth = 48.0
    /// The width the panel opens at.
    public static let initialWidth = 420.0
    /// The height the panel opens at: a heading, six rows and the `Reset` button fit without scrolling.
    public static let initialHeight = 440.0
    /// The smallest height the panel can be resized to.
    public static let minimumHeight = 240.0
    /// The narrowest width at which a label and a control fit side by side.
    public static let minimumWidth = 2 * inset + minimumLabelWidth + spacing + minimumControlWidth

    /// How wide a row's label column is.
    public let labelWidth: Double
    /// How wide a row's control column is.
    public let controlWidth: Double

    public init(width: Double) {
        let usable = width.isFinite ? max(width - 2 * Self.inset, 0) : 0
        let labelWidth = min(max(usable * Self.labelShare, Self.minimumLabelWidth), Self.maximumLabelWidth)
        self.labelWidth = labelWidth
        controlWidth = max(usable - labelWidth - Self.spacing, Self.minimumControlWidth)
    }
}
