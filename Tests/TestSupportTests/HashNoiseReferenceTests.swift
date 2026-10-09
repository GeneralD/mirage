import TestSupport
import Testing

/// The Swift reference on its own: deterministic, in range, and shaped the way
/// the prelude documents it. Agreement with the GPU is the `hash-noise parity`
/// suite's (`make test-gpu`).
@Suite("HashNoiseReference")
struct HashNoiseReferenceTests {
    private static func coordinate(_ generator: inout SeededGenerator) -> Float {
        Float.random(in: -1000...1000, using: &generator)
    }

    @Test("hash is deterministic, in [0, 1), and a multiple of 2^-24", arguments: Seeds.range(0..<50))
    func hashDeterministicAndInRange(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        for _ in 0..<64 {
            let (x, y, step, hashSeed) = (
                UInt32.random(in: .min ... .max, using: &generator), UInt32.random(in: .min ... .max, using: &generator),
                UInt32.random(in: .min ... .max, using: &generator), UInt32.random(in: .min ... .max, using: &generator)
            )
            let value = HashNoiseReference.hash(x: x, y: y, timeStep: step, seed: hashSeed)
            #expect(value == HashNoiseReference.hash(x: x, y: y, timeStep: step, seed: hashSeed))
            #expect(value >= 0 && value < 1)
            let scaled = value * 16_777_216
            #expect(scaled == scaled.rounded(.down), "24-bit resolution, exact in a Float")
        }
    }

    @Test("noise is deterministic and in [0, 1] for any coordinate, time and seed", arguments: Seeds.range(0..<50))
    func noiseDeterministicAndInRange(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        for _ in 0..<64 {
            let (x, y) = (Self.coordinate(&generator), Self.coordinate(&generator))
            let time = Float.random(in: -100...100, using: &generator)
            let noiseSeed = UInt32.random(in: .min ... .max, using: &generator)
            let value = HashNoiseReference.noise(x: x, y: y, time: time, seed: noiseSeed)
            #expect(value == HashNoiseReference.noise(x: x, y: y, time: time, seed: noiseSeed))
            #expect(value >= 0 && value <= 1)
        }
    }

    @Test("on a lattice point, noise is exactly the hash of that cell and time step", arguments: Seeds.range(0..<50))
    func noiseOnLatticeIsHash(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let (x, y, time) = (
            Int32.random(in: -500...500, using: &generator), Int32.random(in: -500...500, using: &generator),
            Int32.random(in: -50...50, using: &generator)
        )
        let noiseSeed = UInt32.random(in: .min ... .max, using: &generator)
        let noise = HashNoiseReference.noise(x: Float(x), y: Float(y), time: Float(time), seed: noiseSeed)
        let hash = HashNoiseReference.hash(
            x: UInt32(bitPattern: x), y: UInt32(bitPattern: y), timeStep: UInt32(bitPattern: time), seed: noiseSeed)
        #expect(noise == hash)
    }

    @Test("noise is continuous across a cell boundary in space and in time", arguments: Seeds.range(0..<50))
    func noiseIsContinuous(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let edge = Float(Int.random(in: -500...500, using: &generator))
        let (y, time) = (Self.coordinate(&generator), Float.random(in: -100...100, using: &generator))
        let noiseSeed = UInt32.random(in: .min ... .max, using: &generator)
        let across = abs(
            HashNoiseReference.noise(x: edge.nextDown, y: y, time: time, seed: noiseSeed)
                - HashNoiseReference.noise(x: edge, y: y, time: time, seed: noiseSeed))
        let acrossTime = abs(
            HashNoiseReference.noise(x: y, y: y, time: edge.nextDown, seed: noiseSeed)
                - HashNoiseReference.noise(x: y, y: y, time: edge, seed: noiseSeed))
        #expect(across < 1e-3)
        #expect(acrossTime < 1e-3)
    }

    @Test("the seed, the time step and each axis change the hash field", arguments: Seeds.range(0..<50))
    func everyInputMatters(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let base = UInt32.random(in: .min ... .max, using: &generator)
        let cells = (0..<64).map { (x: UInt32($0 % 8), y: UInt32($0 / 8)) }
        let field = { (seedOffset: UInt32, step: UInt32, dx: UInt32, dy: UInt32) in
            cells.map { HashNoiseReference.hash(x: $0.x &+ dx, y: $0.y &+ dy, timeStep: step, seed: base &+ seedOffset) }
        }
        let reference = field(0, 0, 0, 0)
        for other in [field(1, 0, 0, 0), field(0, 1, 0, 0), field(0, 0, 1000, 0), field(0, 0, 0, 1000)] {
            let differing = zip(reference, other).filter { $0 != $1 }.count
            #expect(differing >= 60, "\(differing) of 64 cells differ")
        }
    }
}
