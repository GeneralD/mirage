import TestSupport
import Testing

/// The property-test driver has to be reproducible, or a failing seed could
/// not be replayed from the assertion message.
@Suite struct SeededGeneratorTests {
    @Test func theSameSeedReplaysTheSameSequence() {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        let a = (0..<16).map { _ in first.next() }
        let b = (0..<16).map { _ in second.next() }
        #expect(a == b)
        #expect(first.seed == 42, "the seed stays readable for the failure message")
    }

    @Test func differentSeedsStartDifferentSequences() {
        let firstValues = standardSeeds.map { seed in
            var generator = SeededGenerator(seed: seed)
            return generator.next()
        }
        #expect(Set(firstValues).count == standardSeeds.count)
    }

    @Test func forAllVisitsEveryStandardSeedInOrder() {
        var visited: [UInt64] = []
        forAll { generator in visited.append(generator.seed) }
        #expect(visited == standardSeeds)
        #expect(standardSeeds.count == 32)
    }

    @Test func forAllRethrowsTheBodyFailure() {
        struct Stop: Error {}
        #expect(throws: Stop.self) {
            try forAll(seeds: [1, 2]) { generator in
                if generator.seed == 2 { throw Stop() }
            }
        }
    }
}
