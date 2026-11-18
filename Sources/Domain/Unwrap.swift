/// Branch-free unwrapping for thin-live Gateways: `scripts/check-live-thin.sh`
/// forbids `if` / `guard` in coverage-ignored Gateway files, so an OS call that
/// returns an optional or a status code is checked with these instead. They are
/// no port and belong to no kind, so they sit at the root of `Domain`, the one
/// module every Gateway imports; one DataSource uses them too
/// (`StreamOutputDataSourceImpl`, which sends through a stream handle that may
/// not be started yet). The coverage-ignored rule allows these two and no other
/// implementation in `Domain` (`.claude/rules/coverage-ignored-modules.md`).
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
