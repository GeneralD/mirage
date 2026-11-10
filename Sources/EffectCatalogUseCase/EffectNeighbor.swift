import Domain

/// The effect that a next or previous step moves to from `selection`, among the entries that are
/// ready (`availability == .ready`), in catalog order. A broken package is passed over.
///
/// From a candidate, `.next` is the one after it and `.previous` the one before, wrapping round at
/// the ends. A `selection` that is `nil` or not a candidate (a broken package is the chosen one, say)
/// goes to the first candidate for `.next` and to the last for `.previous`. The result is `nil` when
/// there is no candidate, and when the only candidate is the selection itself: the rule never
/// returns the effect it was asked from.
func effectNeighbor(of selection: EffectID?, in entries: [EffectCatalogEntry], step: EffectStep) -> EffectID? {
    let candidates = entries.filter { $0.availability == .ready }.map(\.id)
    guard let first = candidates.first, let last = candidates.last else { return nil }
    guard let index = selection.flatMap({ candidates.firstIndex(of: $0) }) else {
        return step == .next ? first : last
    }
    guard candidates.count > 1 else { return nil }
    let offset = step == .next ? 1 : candidates.count - 1
    return candidates[(index + offset) % candidates.count]
}
