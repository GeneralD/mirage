/// The preview pane's frame in the effect picker at a given container width: the pane takes the
/// width between the picker's insets (`EffectPickerGeometry.inset`), and its height is that width at
/// `aspectRatio`, capped at `maximumHeight`. A pure value so that the numbers are tested here; the
/// View only maps them to pixels.
///
/// A container that is not finite, or no wider than the insets, gives an empty pane. Below the cap
/// the pane keeps the 16:9 shape; at and above it, the pane stays `maximumHeight` tall and the
/// extra width is left to the letterbox that the drawing side paints.
public struct PreviewGeometry: Sendable, Hashable {
    /// The shape of the pane: 16 wide for every 9 high.
    public static let aspectRatio = 16.0 / 9.0
    /// The tallest the pane gets, however wide the picker is.
    public static let maximumHeight = 240.0
    /// The corner radius of the pane.
    public static let cornerRadius = 8.0
    /// The least content height of a picker window that shows the pane: the search field, the status
    /// row, a pane at its maximum height, the switch and one row of the grid.
    public static let minimumContentHeight = 560.0

    /// How wide the pane is: the container's width between the picker's insets; never negative.
    public let width: Double
    /// How tall the pane is: `width` at `aspectRatio`, capped at `maximumHeight`.
    public let height: Double

    public init(containerWidth: Double) {
        let usable = containerWidth.isFinite ? max(containerWidth - 2 * EffectPickerGeometry.inset, 0) : 0
        width = usable
        height = min(usable / Self.aspectRatio, Self.maximumHeight)
    }
}
