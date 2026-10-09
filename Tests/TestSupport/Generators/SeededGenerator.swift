/// SplitMix64: a tiny, fast, well-distributed generator whose whole state is one
/// seed, so a property test that fails prints the seed and replays exactly.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    public let seed: UInt64
    private var state: UInt64

    public init(seed: UInt64) {
        self.seed = seed
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        let z1 = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9
        let z2 = (z1 ^ (z1 >> 27)) &* 0x94D0_49BB_1331_11EB
        return z2 ^ (z2 >> 31)
    }
}

/// The seeds every property test runs by default — enough to shake out an
/// ordering bug, few enough to keep `swift test` fast. Pass as `arguments:` to
/// a parameterized `@Test`, or drive `forAll`.
public let standardSeeds: [UInt64] = Array(0..<32)

/// Runs `body` once per seed with a fresh generator. The seed is in the thrown
/// error's path when `body` fails, because the generator carries it.
public func forAll(seeds: [UInt64] = standardSeeds, _ body: (inout SeededGenerator) throws -> Void) rethrows {
    for seed in seeds {
        var generator = SeededGenerator(seed: seed)
        try body(&generator)
    }
}
