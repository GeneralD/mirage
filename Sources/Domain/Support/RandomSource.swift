import Dependencies

/// The randomness seam that effects draw from (hash and noise seeds). Every draw goes through this port, so
/// a test pins the values and the live source is injected rather than read from the system.
public protocol RandomSource: Sendable {
    /// A value in `0..<upperBound`; a bound of 0 draws 0.
    func next(below upperBound: UInt64) -> UInt64
}

public enum RandomSourceKey: TestDependencyKey {
    /// Pure port: a fixed draw is a safe default, so tests that do not care
    /// about randomness need no override.
    public static let testValue: any RandomSource = FrozenRandomSource()
}

extension DependencyValues {
    public var randomSource: any RandomSource {
        get { self[RandomSourceKey.self] }
        set { self[RandomSourceKey.self] = newValue }
    }
}

private struct FrozenRandomSource: RandomSource {
    func next(below upperBound: UInt64) -> UInt64 { 0 }
}
