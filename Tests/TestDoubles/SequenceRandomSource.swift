import Domain
import TestSupport

/// Draws the given values in order, each reduced below the bound of its call, and starts again from the first
/// value once they are used up. The i-th call (0-based) returns `values[i % values.count] % upperBound`; a bound
/// of 0 or an empty sequence returns 0. Every call moves the index on, a bound of 0 included, and `draws`
/// records the bound of every call in call order.
public final class SequenceRandomSource: RandomSource, Sendable {
    private let values: [UInt64]
    private let calls = Locked(0)
    public let draws = Collector<UInt64>()

    public init(_ values: [UInt64]) {
        self.values = values
    }

    public func next(below upperBound: UInt64) -> UInt64 {
        calls.withLock { (index: inout Int) -> UInt64 in
            let position = index
            index += 1
            draws.append(upperBound)
            guard upperBound != 0, !values.isEmpty else { return 0 }
            return values[position % values.count] % upperBound
        }
    }
}
