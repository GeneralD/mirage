import Domain

// The parameter writes that wait for the debounce (`docs/hackathon/mvp-cd/specs/parameters.md`, pure policy). A value
// type with one entry per effect: the latest write of an effect replaces its earlier ones, and a generation lets a
// sleeping debounce tell whether a later write came after it, so only the last write of a burst is persisted.

/// The values one effect had written and not yet persisted.
struct PendingParameterWrite: Equatable, Sendable {
    let id: EffectID
    let values: [String: EffectParameterValue]
}

/// The writes waiting to be persisted, at most one entry per effect.
struct PendingParameterWrites: Equatable, Sendable {
    private var entries: [EffectID: [String: EffectParameterValue]] = [:]

    /// The number of `record` calls so far. A debounce keeps the number it was started with and drains only while it is
    /// still the current one. Draining does not reset it.
    private(set) var generation = 0

    var isEmpty: Bool {
        entries.isEmpty
    }

    func values(of id: EffectID) -> [String: EffectParameterValue]? {
        entries[id]
    }

    /// Replaces the entry of `id` and keeps the other effects' entries. Returns the new generation, so the first call
    /// returns 1.
    mutating func record(_ values: [String: EffectParameterValue], of id: EffectID) -> Int {
        entries[id] = values
        generation += 1
        return generation
    }

    /// Every pending write, emptying the set, when `generation` is still the current one. Otherwise nothing is returned
    /// and nothing changes.
    mutating func drained(ifGeneration generation: Int) -> [PendingParameterWrite] {
        guard generation == self.generation else { return [] }
        return drainedAll()
    }

    /// Every pending write, emptying the set, whatever the generation.
    mutating func drainedAll() -> [PendingParameterWrite] {
        let writes = entries.map { PendingParameterWrite(id: $0.key, values: $0.value) }
        entries.removeAll()
        return writes.sorted { ($0.id.origin.rawValue, $0.id.key) < ($1.id.origin.rawValue, $1.id.key) }
    }
}
