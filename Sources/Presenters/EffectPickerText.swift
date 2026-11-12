import Domain
import Foundation

// The words, flags and artwork of the effect picker, as pure functions of the catalog's state and
// the search, so that `EffectPickerPresenter` only moves them into its `@Published` values. The
// second line and the status are the menu's (`MenuBarText`), so the two never word the same thing
// differently.

/// The cells for `state` whose name or author contains the search, in the catalog's order. A
/// search that is empty once trimmed matches every entry.
func pickerCells(of state: EffectCatalogState, matching query: String) -> [EffectPickerCell] {
    let term = searchTerm(of: query)
    return state.entries
        .filter { entry in term.isEmpty || matches(entry, term) }
        .map { entry in pickerCell(of: entry, in: state) }
}

/// What the grid says in place of cells: `nil` while there is a cell to show or nothing has been
/// listed yet, and that nothing matches when a search hides every entry.
func pickerEmptyMessage(of state: EffectCatalogState, matching query: String) -> String? {
    let term = searchTerm(of: query)
    guard !term.isEmpty, !state.entries.isEmpty, pickerCells(of: state, matching: query).isEmpty else { return nil }
    return "No effects match “\(term)”"
}

/// What a cell draws above its name: the thumbnail the catalog carries for a package that can be
/// chosen, with the entry's own tile to fall back on when the bytes do not decode, or that tile
/// alone when there is none to draw: the entry has no thumbnail (a bundled effect, a package whose
/// manifest names none or names one that cannot be used), or it is a broken package, whose
/// manifest is not trusted for its picture any more than for its name. The catalog gives a broken
/// package none, and this does not rely on that, as `help(of:)` does not rely on it for a description.
func artwork(of entry: EffectCatalogEntry) -> EffectArtwork {
    let tile = placeholder(of: entry)
    guard entry.availability == .ready, let thumbnail = entry.thumbnail else { return .placeholder(tile) }
    return .image(thumbnail, fallback: tile)
}

/// The tile a cell draws when it has no picture to show: the entry has no thumbnail, or its
/// thumbnail does not decode.
func placeholder(of entry: EffectCatalogEntry) -> EffectPlaceholder {
    EffectPlaceholder(monogram: monogram(of: entry.displayName), hue: placeholderHue(of: entry.id))
}

/// The first letter or digit of each of the first two words that have one, upper-cased and one
/// character each: `"Chromatic Grain"` is `"CG"`, `"[WIP] Ripple"` is `"WR"`.
func monogram(of name: String) -> String {
    name.split(whereSeparator: \.isWhitespace)
        .compactMap { word in word.first { $0.isLetter || $0.isNumber } }
        .prefix(2)
        .map { String($0.uppercased().prefix(1)) }
        .joined()
}

/// A hue in `0..<1`, one of 360, from a 64-bit FNV-1a hash of `<origin>:<key>` in Unicode's
/// composed form (NFC), so two keys that are the same `EffectID` get the same hue however their
/// accents were typed. Not `hashValue`, which Swift seeds afresh in every process: the tile of an
/// effect must not change colour between launches.
func placeholderHue(of id: EffectID) -> Double {
    let text = "\(id.origin.rawValue):\(id.key)".precomposedStringWithCanonicalMapping
    let hash = text.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { hash, byte in
        (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    return Double(hash % 360) / 360
}

private func pickerCell(of entry: EffectCatalogEntry, in state: EffectCatalogState) -> EffectPickerCell {
    EffectPickerCell(
        id: entry.id,
        title: entry.displayName,
        detail: MenuBarText.detail(of: entry, in: state),
        isSelected: entry.id == state.selection,
        isEnabled: entry.availability == .ready && state.disabled[entry.id] == nil,
        help: help(of: entry, in: state),
        artwork: artwork(of: entry))
}

/// What the cell can only abbreviate: for an effect that can be chosen, its name and author, and
/// the manifest's description on a line of its own after them; for an effect that health has
/// switched off, its name and the reason; for a broken package, the name and why it cannot be
/// chosen.
private func help(of entry: EffectCatalogEntry, in state: EffectCatalogState) -> String {
    switch entry.availability {
    case .ready:
        if let disabled = state.disabled[entry.id] {
            return "\(entry.displayName) is disabled: \(MenuBarText.reason(disabled))"
        }
        let name = entry.author.map { "\(entry.displayName) by \($0)" } ?? entry.displayName
        return [name, helpDescription(of: entry)].compactMap(\.self).joined(separator: "\n")
    case .broken(let problem):
        return "\(entry.displayName) cannot be chosen: \(MenuBarText.reason(problem))"
    }
}

/// The most Unicode scalars of a description that a hover shows: a longer one is cut. It bounds the
/// description alone, in scalars and not in `Character`s (a base letter followed by a thousand
/// combining marks is one `Character`), so that the hover does not grow with a long one and the work
/// of `helpDescription`, which the picker repeats on every keystroke, does not either. The name and the
/// author are not cut: the cell shows them in full too.
private let helpDescriptionLimit = 280

/// The entry's description for the hover: without the whitespace around it, cut at
/// `helpDescriptionLimit` scalars with an ellipsis when something other than whitespace follows the
/// cut within the next `helpDescriptionLimit` scalars, and `nil` when it says nothing (the manifest
/// names none, or a blank one). It reads the whitespace before the text, the text up to the cut and
/// no more than `helpDescriptionLimit` scalars past it, so a long text is not read through on every
/// keystroke; a gap of whitespace longer than that after the cut hides what follows it without an ellipsis.
private func helpDescription(of entry: EffectCatalogEntry) -> String? {
    guard let description = entry.description else { return nil }
    let content = description.unicodeScalars.drop { $0.properties.isWhitespace }
    let head = String(Substring(content.prefix(helpDescriptionLimit))).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !head.isEmpty else { return nil }
    let rest = content.dropFirst(helpDescriptionLimit).prefix(helpDescriptionLimit)
    return rest.contains { !$0.properties.isWhitespace } ? head + "…" : head
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
