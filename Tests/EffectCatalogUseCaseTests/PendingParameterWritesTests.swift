import Domain
import Testing

@testable import EffectCatalogUseCase

/// The writes waiting for the debounce (`PendingParameterWrites`). Each rule of the type's interface is one test, named
/// as the spec sentence it checks.
@Suite("PendingParameterWrites", .timeLimit(.minutes(1)))
struct PendingParameterWritesTests {
    private static let bloom = EffectID(origin: .bundled, key: "bloom")
    private static let wave = EffectID(origin: .bundled, key: "wave")
    private static let zoom = EffectID(origin: .bundled, key: "z")
    private static let ripple = EffectID(origin: .package, key: "ripple")
    private static let alpha = EffectID(origin: .package, key: "a")

    private static func gain(_ value: Float) -> [String: EffectParameterValue] {
        ["gain": .float(value)]
    }

    @Test("a new set is empty, has no writes for any effect, and is at generation 0")
    func newSetIsEmpty() {
        var writes = PendingParameterWrites()
        #expect(writes.isEmpty)
        #expect(writes.generation == 0)
        #expect(writes.values(of: Self.bloom) == nil)
        #expect(writes.drained(ifGeneration: 0) == [])
    }

    @Test("record returns the generations 1, 2, 3 in call order, whichever effect each call is for")
    func recordCountsGenerations() {
        var writes = PendingParameterWrites()
        #expect(writes.record(Self.gain(0.1), of: Self.bloom) == 1)
        #expect(writes.record(Self.gain(0.2), of: Self.wave) == 2)
        #expect(writes.record(Self.gain(0.3), of: Self.bloom) == 3)
        #expect(writes.generation == 3)
    }

    @Test("a second record of the same effect replaces its values and keeps one entry for it")
    func secondRecordReplacesSameEffect() {
        var writes = PendingParameterWrites()
        _ = writes.record(Self.gain(0.2), of: Self.bloom)
        _ = writes.record(Self.gain(0.9), of: Self.bloom)
        #expect(writes.values(of: Self.bloom) == Self.gain(0.9))
        #expect(writes.drainedAll() == [PendingParameterWrite(id: Self.bloom, values: Self.gain(0.9))])
    }

    @Test("the writes of two effects both stay pending, and the set is not empty while either is")
    func writesOfTwoEffectsStayPending() {
        var writes = PendingParameterWrites()
        _ = writes.record(Self.gain(0.2), of: Self.bloom)
        _ = writes.record(Self.gain(0.4), of: Self.wave)
        #expect(!writes.isEmpty)
        #expect(writes.values(of: Self.bloom) == Self.gain(0.2))
        #expect(writes.values(of: Self.wave) == Self.gain(0.4))
        #expect(writes.drainedAll().count == 2)
    }

    @Test("a pending write holds the effect and the values it was recorded with")
    func pendingWriteHoldsEffectAndValues() {
        var writes = PendingParameterWrites()
        _ = writes.record(Self.gain(0.5), of: Self.ripple)
        #expect(writes.drainedAll() == [PendingParameterWrite(id: Self.ripple, values: Self.gain(0.5))])
    }

    @Test("drained at the latest generation returns every pending write and leaves nothing pending")
    func drainedAtLatestGenerationReturnsAll() {
        var writes = PendingParameterWrites()
        _ = writes.record(Self.gain(0.2), of: Self.bloom)
        let latest = writes.record(Self.gain(0.4), of: Self.wave)
        #expect(
            writes.drained(ifGeneration: latest) == [
                PendingParameterWrite(id: Self.bloom, values: Self.gain(0.2)),
                PendingParameterWrite(id: Self.wave, values: Self.gain(0.4)),
            ])
        #expect(writes.isEmpty)
    }

    @Test("drained at an older generation returns nothing and keeps every pending write")
    func drainedAtOlderGenerationKeepsWrites() {
        var writes = PendingParameterWrites()
        let older = writes.record(Self.gain(0.2), of: Self.bloom)
        _ = writes.record(Self.gain(0.4), of: Self.wave)
        #expect(writes.drained(ifGeneration: older) == [])
        #expect(writes.values(of: Self.bloom) == Self.gain(0.2))
        #expect(writes.values(of: Self.wave) == Self.gain(0.4))
    }

    @Test("drainedAll returns every pending write whatever the generation, and leaves nothing pending")
    func drainedAllIgnoresGeneration() {
        var writes = PendingParameterWrites()
        let stale = writes.record(Self.gain(0.2), of: Self.bloom)
        _ = writes.record(Self.gain(0.4), of: Self.wave)
        #expect(writes.drained(ifGeneration: stale) == [])
        #expect(
            writes.drainedAll() == [
                PendingParameterWrite(id: Self.bloom, values: Self.gain(0.2)),
                PendingParameterWrite(id: Self.wave, values: Self.gain(0.4)),
            ])
        #expect(writes.isEmpty)
    }

    @Test("a record after a drain continues the generation numbers, and the earlier generation's drained stays empty")
    func recordAfterDrainContinuesGenerations() {
        var writes = PendingParameterWrites()
        let first = writes.record(Self.gain(0.2), of: Self.bloom)
        #expect(writes.drained(ifGeneration: first) == [PendingParameterWrite(id: Self.bloom, values: Self.gain(0.2))])
        let second = writes.record(Self.gain(0.6), of: Self.bloom)
        #expect(second == first + 1)
        #expect(writes.drained(ifGeneration: first) == [])
        #expect(writes.values(of: Self.bloom) == Self.gain(0.6))
    }

    @Test("drained and drainedAll order the writes by origin's raw value, then by key within an origin")
    func drainOrderIsOriginThenKey() {
        var writes = PendingParameterWrites()
        _ = writes.record(Self.gain(0.1), of: Self.alpha)
        _ = writes.record(Self.gain(0.2), of: Self.zoom)
        _ = writes.record(Self.gain(0.3), of: Self.wave)
        _ = writes.record(Self.gain(0.4), of: Self.bloom)
        #expect(writes.drainedAll().map(\.id) == [Self.bloom, Self.wave, Self.zoom, Self.alpha])
    }

    @Test("values(of:) returns nil once the effect's writes have been drained")
    func valuesAreNilAfterDrain() {
        var writes = PendingParameterWrites()
        let latest = writes.record(Self.gain(0.2), of: Self.bloom)
        _ = writes.drained(ifGeneration: latest)
        #expect(writes.values(of: Self.bloom) == nil)
    }
}
