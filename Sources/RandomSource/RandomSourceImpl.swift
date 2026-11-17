import Domain

/// Live `RandomSource`: draws from the system's generator with `UInt64.random(in:)`.
///
/// Effects reach randomness only through the port, so a test pins the draws with a double and this
/// struct is the one place that reads the system's generator. It holds no state of its own.
public struct RandomSourceImpl: RandomSource {
    public init() {}

    /// The closed range `0...upperBound - 1`, with a bound of 0 read as 1, so the port's "a bound of 0
    /// draws 0" needs no branch: the empty range `0..<0` that would trap is never formed.
    public func next(below upperBound: UInt64) -> UInt64 {
        UInt64.random(in: 0...(max(upperBound, 1) - 1))
    }
}
