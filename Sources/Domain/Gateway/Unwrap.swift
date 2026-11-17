/// Branch-free unwrapping for thin-live Gateways: `scripts/check-live-thin.sh`
/// forbids `if` / `guard` in coverage-ignored Gateway files, so an OS call that
/// returns an optional or a status code is checked with these instead. It is not a
/// port, so it sits beside the Gateway ports it serves; one DataSource uses it too
/// (`StreamOutputDataSourceImpl`, which sends through a stream handle that may not
/// be started yet).
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
