import Dependencies
import Domain

/// The real `EffectWatch` (epic #42, D4): arms the watches a listing asks for through
/// `FileWatchGateway` and folds every burst of events into one element on
/// `\.continuousClock`.
///
/// **Arming.** `changes(of:)` arms every directory (`watch(directory:)`, which sees an
/// editor's atomic save) and then every file (`watch(file:)`, which sees an in-place
/// overwrite) of the set *before it returns*, so the watches are live when the call is over:
/// the first change after it (for the Repository, the first one after a catalog it has shown)
/// is buffered until someone iterates the stream, not lost. A path that cannot be watched (it
/// was in the listing and is gone by now) is logged to the developer log and skipped. That
/// costs that path's watch and nothing else, since a throw would cost the whole set; nothing
/// arms the path again or asks for a listing because of it, so the listing stays as it was
/// until some other armed watch hears an event. The stream never ends on its own, not even
/// for an empty set or when nothing could be armed, because `EffectPackageRepository` reads
/// an end it did not cause as the watch being gone.
///
/// **One element per burst.** Whichever watch fires, the event restarts the same quiet
/// period (`quietPeriod`, 200 ms); an element is yielded when a period ends with no event
/// after the one that started it. Every event gets a number and starts a sleep of its own on
/// the clock; when a sleep ends, its number is compared with the newest one, so a period that
/// a later event replaced yields nothing. The watches' callbacks only post to a stream of
/// signals and one task per `changes(of:)` reads them in order, which is why the numbers and
/// the yield need no lock and no shared state.
///
/// **Ending.** When the consumer lets go (cancels its task or stops iterating) every watch
/// that was armed is stopped, exactly once, the sleeps still running are cancelled and the
/// period in progress is dropped. A late event after that reaches nobody: the watches are
/// stopped, and the signals and the element stream are terminated.
public struct EffectWatchDataSourceImpl: Sendable {
    /// How long the files must be quiet before a burst of events counts as over.
    public static let quietPeriod: Duration = .milliseconds(200)

    @Dependency(\.fileWatchGateway) private var fileWatchGateway
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension EffectWatchDataSourceImpl: EffectWatch {
    public func changes(of watchSet: EffectWatchSet) -> AsyncStream<Void> {
        let (changes, element) = AsyncStream<Void>.makeStream()
        let (signals, signal) = AsyncStream<Signal>.makeStream()
        let handles = arm(watchSet) { _ = signal.yield(.changed) }
        let clock = clock
        let debouncing = Task { await Self.debounce(signals, feeding: signal, into: element, on: clock) }
        element.onTermination = { _ in
            for handle in handles { handle.stop() }
            signal.finish()
            debouncing.cancel()
        }
        return changes
    }
}

extension EffectWatchDataSourceImpl {
    /// What the debouncing task is told: a watch fired, or the sleep that an event started has ended.
    fileprivate enum Signal: Sendable {
        case changed
        case quiet(after: Int)
    }

    private func arm(_ watchSet: EffectWatchSet, onChange: @escaping @Sendable () -> Void) -> [any FileWatchHandle] {
        let directories = watchSet.directories.compactMap { path in
            armed(path, as: "directory") { try fileWatchGateway.watch(directory: path, onChange: onChange) }
        }
        let files = watchSet.files.compactMap { path in
            armed(path, as: "file") { try fileWatchGateway.watch(file: path, onChange: onChange) }
        }
        return directories + files
    }

    private func armed(_ path: String, as kind: String, _ attempt: () throws -> any FileWatchHandle) -> (any FileWatchHandle)? {
        do {
            return try attempt()
        } catch {
            developerLog.record(.effect, "could not watch \(kind) \(path), skipped: \(error)")
            return nil
        }
    }

    /// Reads the signals one at a time until they end, so `latest` is touched by this task
    /// alone. Each event starts a sleep (a child of the group, so ending the loop cancels
    /// every one still running) that reports back through the same signals; only the report
    /// of the newest event yields.
    private static func debounce(
        _ signals: AsyncStream<Signal>,
        feeding signal: AsyncStream<Signal>.Continuation,
        into element: AsyncStream<Void>.Continuation,
        on clock: any Clock<Duration>
    ) async {
        await withDiscardingTaskGroup { group in
            // The number of the newest event: bumped per event, compared when a sleep ends.
            var latest = 0
            for await received in signals {
                switch received {
                case .changed:
                    latest += 1
                    let number = latest
                    group.addTask {
                        guard (try? await clock.sleep(for: Self.quietPeriod)) != nil else { return }
                        signal.yield(.quiet(after: number))
                    }
                case .quiet(let number):
                    guard number == latest else { continue }
                    element.yield(())
                }
            }
            group.cancelAll()
        }
    }
}
