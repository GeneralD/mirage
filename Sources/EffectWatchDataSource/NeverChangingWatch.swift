import Domain

/// A watch that never hears anything: the stream it returns yields no element and ends
/// only when its consumer lets go, so a catalog built on it lists once and stays as it
/// was. Registered as the host's live `EffectWatch` until the real DataSource lands in
/// this module (epic #42, D10). It arms nothing, so there is nothing to stop.
public struct NeverChangingWatch: EffectWatch, Sendable {
    public init() {}

    public func changes(of watchSet: EffectWatchSet) -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}
