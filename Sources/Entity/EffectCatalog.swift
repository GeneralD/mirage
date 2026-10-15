/// Whether an effect in the menu can be chosen: a package that failed to load is
/// shown disabled, with the reason (epic #42, D3).
public enum EffectAvailability: Sendable, Hashable {
    case ready
    case broken(EffectPackageProblem)
}

/// One row of the effects menu.
public struct EffectCatalogEntry: Sendable, Hashable {
    public let id: EffectID
    /// What the menu shows: a bundled effect's name, a package's manifest `name`
    /// (its folder name while the manifest cannot be read).
    public let displayName: String
    /// Always `id.origin`; a field of its own because the menu groups by it.
    public let origin: EffectOrigin
    public let availability: EffectAvailability
    /// The manifest's `author`, for the menu to show beside the name; `nil` for a bundled
    /// effect, for a manifest that names none, and for a package whose manifest cannot be read.
    public let author: String?

    public init(id: EffectID, displayName: String, origin: EffectOrigin, availability: EffectAvailability, author: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.origin = origin
        self.availability = availability
        self.author = author
    }
}

/// What came of choosing an effect (`EffectCatalogUseCase.select`).
public enum EffectSelectionOutcome: Sendable, Hashable {
    /// The runtime compiled it; it is the effect `apply` runs.
    case prepared
    /// The runtime could not compile it. The pipeline passes frames through
    /// (epic #42, D5); fixing the source selects it again by itself.
    case failed(EffectFailure)
    /// There was nothing to prepare: the package is broken (its problem), or no longer there (`nil`).
    case unavailable(EffectPackageProblem?)
}

/// What the menu needs to know, in one value: the rows, the chosen effect and how the
/// last attempt to run it went (`nil` before the first one).
public struct EffectCatalogState: Sendable, Hashable {
    public let entries: [EffectCatalogEntry]
    public let selection: EffectID
    public let outcome: EffectSelectionOutcome?

    public init(entries: [EffectCatalogEntry], selection: EffectID, outcome: EffectSelectionOutcome? = nil) {
        self.entries = entries
        self.selection = selection
        self.outcome = outcome
    }
}
