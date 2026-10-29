/// One cell of the effect picker's grid as the Presenter shows it (#12): the catalog's entry
/// turned into the words, flags and artwork a View maps to pixels. The Presenter decides the
/// values; the View only draws them.
public struct EffectPickerCell: Sendable, Hashable, Identifiable {
    public let id: EffectID
    /// The effect's name.
    public let title: String
    /// A second line: the package's author, or why a broken package cannot be chosen.
    /// `nil` when there is nothing to add.
    public let detail: String?
    /// Whether this is the effect that is running: the menu's checked row.
    public let isSelected: Bool
    /// `false` for a package that failed to load.
    public let isEnabled: Bool
    /// What the cell says when the pointer rests on it.
    public let help: String
    /// What the cell draws above its name.
    public let artwork: EffectArtwork

    public init(
        id: EffectID, title: String, detail: String?, isSelected: Bool, isEnabled: Bool, help: String, artwork: EffectArtwork
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.help = help
        self.artwork = artwork
    }
}

/// What a picker cell draws above its name. Every cell draws a placeholder until the catalog
/// carries a package's thumbnail (#12); the image joins this enum as a case of its own then.
public enum EffectArtwork: Sendable, Hashable {
    /// A tile of one hue with the effect's initials on it.
    case placeholder(EffectPlaceholder)
}

/// The tile a cell draws while there is no thumbnail: the same effect gets the same tile on every
/// launch and every machine, so it can be recognised by its colour.
public struct EffectPlaceholder: Sendable, Hashable {
    /// Up to two letters: the first of each of the name's first two words, upper-cased.
    public let monogram: String
    /// The tile's hue, in `0..<1`.
    public let hue: Double

    public init(monogram: String, hue: Double) {
        self.monogram = monogram
        self.hue = hue
    }
}
