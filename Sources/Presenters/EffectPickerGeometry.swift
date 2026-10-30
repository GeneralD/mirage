/// The effect picker's grid at a given width (#12): as many columns as fit cells of at least
/// `minimumCellWidth`, `spacing` apart, inside an `inset` on each side, the cells widened to fill
/// the row. A pure value so that the layout is tested here; `EffectPickerView` only maps it to a
/// `LazyVGrid` (`Views` is coverage-ignored and holds no logic).
///
/// Every width gives at least one column: one narrower than a cell gets a single column as wide as
/// it allows (nothing, below the insets). A width that is not finite counts as none, and the
/// column count stops at `maximumColumns`, where the cells widen instead: no window is that wide,
/// and the count stays an `Int` for any `Double`.
public struct EffectPickerGeometry: Sendable, Hashable {
    /// The narrowest a cell gets while more than one column fits.
    public static let minimumCellWidth = 120.0
    /// The gap between two columns, and between two rows.
    public static let spacing = 12.0
    /// The margin on each side of the grid.
    public static let inset = 16.0
    /// The most columns a row holds, however wide the picker is.
    public static let maximumColumns = 32

    /// How many cells a row holds; at least one.
    public let columns: Int
    /// How wide each cell is, so that the row fills the width between the insets.
    public let cellWidth: Double

    public init(width: Double) {
        let usable = width.isFinite ? max(width - 2 * Self.inset, 0) : 0
        let fitting = ((usable + Self.spacing) / (Self.minimumCellWidth + Self.spacing)).rounded(.down)
        let columns = Int(min(max(fitting, 1), Double(Self.maximumColumns)))
        self.columns = columns
        cellWidth = (usable - Self.spacing * Double(columns - 1)) / Double(columns)
    }
}
