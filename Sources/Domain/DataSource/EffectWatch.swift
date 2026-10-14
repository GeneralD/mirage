import Dependencies

/// `EffectWatchDataSource`: tells the catalog that something it listed has changed
/// (epic #42, D4). It arms a directory watch on each of `directories` and a file
/// watch on each of `files` through `FileWatchGateway`, and folds a burst of events
/// into one element on `\.continuousClock` (a 200 ms quiet period), so an editor's
/// save that touches the file three times is one re-listing.
public protocol EffectWatch: Sendable {
    /// One element per burst of changes under `watchSet`, until the stream ends.
    ///
    /// - Everything in `watchSet` is armed before this returns, so a change made
    ///   after the call is not lost, and a path that cannot be watched is skipped
    ///   (the next listing arms again).
    /// - A burst is one element, however many events it was made of.
    /// - Ending the stream (the consumer's task is cancelled or it stops iterating)
    ///   stops every watch it armed, exactly once each.
    func changes(of watchSet: EffectWatchSet) -> AsyncStream<Void>
}

public enum EffectWatchKey: TestDependencyKey {
    public static let testValue: any EffectWatch = UnimplementedEffectWatch()
}

extension DependencyValues {
    public var effectWatch: any EffectWatch {
        get { self[EffectWatchKey.self] }
        set { self[EffectWatchKey.self] = newValue }
    }
}

private struct UnimplementedEffectWatch: EffectWatch {
    func changes(of watchSet: EffectWatchSet) -> AsyncStream<Void> {
        reportIssue("EffectWatch.changes not implemented")
        return AsyncStream { $0.finish() }
    }
}
