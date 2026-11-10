/// One row of the effects menu as the Presenter shows it (epic #42, D9): the catalog's
/// entry turned into the words and flags a View maps to pixels. The Presenter decides
/// the values; the View only draws them.
public struct EffectMenuItem: Sendable, Hashable, Identifiable {
    public let id: EffectID
    /// The effect's name.
    public let title: String
    /// A second line: the package's author, or why a broken package cannot be chosen.
    /// `nil` when there is nothing to add.
    public let detail: String?
    /// Whether this is the effect that is running.
    public let isSelected: Bool
    /// `false` for a package that failed to load.
    public let isEnabled: Bool
    /// The title of the Re-enable operation for a disabled effect; `nil` when the row offers no such operation.
    public let reenableTitle: String?

    public init(id: EffectID, title: String, detail: String?, isSelected: Bool, isEnabled: Bool, reenableTitle: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.reenableTitle = reenableTitle
    }
}
