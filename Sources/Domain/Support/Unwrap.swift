/// Branch-free unwrapping for thin-live Gateways: `scripts/check-live-thin.sh`
/// forbids `if` / `guard` in coverage-ignored Gateway files, so an OS call that
/// returns an optional or a status code is checked with these instead.
extension Optional {
    public func orThrow(_ error: @autoclosure () -> any Error) throws -> Wrapped {
        try self ?? { throw error() }()
    }
}

extension Bool {
    /// Throws `error` when `self` is `false`.
    public func orThrow(_ error: @autoclosure () -> any Error) throws {
        try self ? () : { throw error() }()
    }
}
