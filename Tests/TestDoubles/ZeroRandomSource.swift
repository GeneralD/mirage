import Domain

/// Every draw is 0, whatever the bound.
public struct ZeroRandomSource: RandomSource {
    public init() {}

    public func next(below upperBound: UInt64) -> UInt64 { 0 }
}
