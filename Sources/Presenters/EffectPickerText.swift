import Domain
import Foundation

// The words, flags and placeholder tiles of the effect picker, as pure functions of the catalog's
// state and the search, so that `EffectPickerPresenter` only moves them into its `@Published`
// values. The second line and the status are the menu's (`MenuBarText`), so the two never word
// the same thing differently.

/// The cells for `state` whose name or author contains the search, in the catalog's order. A
/// search that is empty once trimmed matches every entry.
func pickerCells(of state: EffectCatalogState, matching query: String) -> [EffectPickerCell] {
    let term = searchTerm(of: query)
    return state.entries
        .filter { entry in term.isEmpty || matches(entry, term) }
        .map { entry in pickerCell(of: entry, selection: state.selection) }
}

/// What the grid says in place of cells: `nil` while there is a cell to show or nothing has been
/// listed yet, and that nothing matches when a search hides every entry.
func pickerEmptyMessage(of state: EffectCatalogState, matching query: String) -> String? {
    let term = searchTerm(of: query)
    guard !term.isEmpty, !state.entries.isEmpty, pickerCells(of: state, matching: query).isEmpty else { return nil }
    return "No effects match “\(term)”"
}

/// The tile a cell draws while the catalog carries no thumbnail.
func placeholder(of entry: EffectCatalogEntry) -> EffectPlaceholder {
    EffectPlaceholder(monogram: monogram(of: entry.displayName), hue: placeholderHue(of: entry.id))
}

/// The first letter of each of the first two words, upper-cased: `"Chromatic Grain"` is `"CG"`.
func monogram(of name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map { $0.uppercased() }.joined()
}

/// A hue in `0..<1`, one of 360, from a 64-bit FNV-1a hash of `<origin>:<key>`. Not `hashValue`,
/// which Swift seeds afresh in every process: the tile of an effect must not change colour between
/// launches.
func placeholderHue(of id: EffectID) -> Double {
    let hash = "\(id.origin.rawValue):\(id.key)".utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { hash, byte in
        (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    return Double(hash % 360) / 360
}

private func pickerCell(of entry: EffectCatalogEntry, selection: EffectID) -> EffectPickerCell {
    EffectPickerCell(
        id: entry.id,
        title: entry.displayName,
        detail: MenuBarText.detail(of: entry),
        isSelected: entry.id == selection,
        isEnabled: entry.availability == .ready,
        help: help(of: entry),
        artwork: .placeholder(placeholder(of: entry)))
}

/// The whole of what the cell can only abbreviate: the name and the author, or the name and why
/// it cannot be chosen.
private func help(of entry: EffectCatalogEntry) -> String {
    switch (entry.availability, entry.author) {
    case (.ready, let author?): "\(entry.displayName) by \(author)"
    case (.ready, nil): entry.displayName
    case (.broken(let problem), _): "\(entry.displayName) cannot be chosen: \(MenuBarText.reason(problem))"
    }
}

/// The search as it is matched: without the whitespace around it.
private func searchTerm(of query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Whether the entry's name or author contains `term`, ignoring case, accents and full- or
/// half-width forms, under no locale, so a search finds the same cells on every machine.
private func matches(_ entry: EffectCatalogEntry, _ term: String) -> Bool {
    [entry.displayName, entry.author].compactMap(\.self).contains { text in
        text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
    }
}
