import Domain

/// Live `RandomSource`: draws from the system's generator with `UInt64.random(in:)`.
///
/// Effects reach randomness only through the port, so a test pins the draws with a double and this
/// struct is the one place that reads the system's generator. It holds no state of its own.
public struct RandomSourceImpl: RandomSource {
    public init() {}

    public func next(below upperBound: UInt64) -> UInt64 {
        guard upperBound != 0 else { return 0 }
        return UInt64.random(in: 0..<upperBound)
    }
}
