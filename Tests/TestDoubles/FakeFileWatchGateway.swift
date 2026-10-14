import Domain
import Foundation
import TestSupport

/// `FileWatchGateway` the test fires by hand: `watch` arms and records, `fire(path)`
/// reports a change to every live watch on exactly that path (a directory watch and a
/// file watch on the same string both hear it), and nothing happens on its own. A
/// stopped watch never fires again, as with the live gateway.
///
/// `isBalanced` is the invariant the DataSource suites assert after the subject has
/// ended: every watch it armed was stopped, and none twice. The live handle cannot see
/// a double stop (cancelling a cancelled source does nothing), so the fake counts it:
/// `doubleStopCount`, and `isBalanced` is `false`. Like the other fakes that record,
/// the watch is stored before it is recorded, so a test that waited on `watches` can
/// `fire` at once without the event falling into the gap.
public final class FakeFileWatchGateway: FileWatchGateway, Sendable {
    public enum Kind: Sendable, Hashable {
        case directory
        case file
    }

    public struct Watch: Sendable, Hashable {
        public let kind: Kind
        public let path: String

        public init(kind: Kind, path: String) {
            self.kind = kind
            self.path = path
        }
    }

    private struct Armed {
        let watch: Watch
        let onChange: @Sendable () -> Void
        var isStopped = false
    }

    private struct State {
        var armed: [Armed] = []
        var failures: [String: any Error] = [:]
        var stopCount = 0
        var doubleStopCount = 0
    }

    private let state = Locked(State())
    /// Every watch that was armed, in order. A watch that threw is not here.
    public let watches = Collector<Watch>()

    public init() {}

    // MARK: Hooks

    /// Reports a change to every live watch on `path`, on the calling thread, and says
    /// how many heard it. `0` means nothing is watching that path (or every watch on it
    /// was stopped), which a test can assert.
    @discardableResult
    public func fire(_ path: String) -> Int {
        let listeners = state.withLock { $0.armed.filter { !$0.isStopped && $0.watch.path == path }.map(\.onChange) }
        for listener in listeners { listener() }
        return listeners.count
    }

    /// Makes arming a watch on `path` throw `error`, as a path that does not exist does,
    /// until the next call with `nil` clears it.
    public func failWatch(of path: String, with error: (any Error)?) {
        state.withLock { $0.failures[path] = error }
    }

    /// The watches armed and not yet stopped.
    public var activeWatches: [Watch] {
        state.withLock { $0.armed.filter { !$0.isStopped }.map(\.watch) }
    }

    /// Watches armed, ignoring whether they were stopped since.
    public var watchCount: Int { watches.count }

    /// Watches stopped, counted once each.
    public var stopCount: Int { state.withLock { $0.stopCount } }

    /// Stops of a watch that was already stopped.
    public var doubleStopCount: Int { state.withLock { $0.doubleStopCount } }

    /// Every watch armed was stopped, and none was stopped twice.
    public var isBalanced: Bool {
        state.withLock { $0.stopCount == $0.armed.count && $0.doubleStopCount == 0 }
    }

    // MARK: FileWatchGateway

    public func watch(directory: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        try arm(Watch(kind: .directory, path: directory), onChange: onChange)
    }

    public func watch(file: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        try arm(Watch(kind: .file, path: file), onChange: onChange)
    }

    private func arm(_ watch: Watch, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        let index = try state.withLock { state -> Int in
            if let failure = state.failures[watch.path] { throw failure }
            state.armed.append(Armed(watch: watch, onChange: onChange))
            return state.armed.count - 1
        }
        watches.append(watch)
        return Handle(gateway: self, index: index)
    }

    fileprivate func stop(_ index: Int) {
        state.withLock { state in
            guard !state.armed[index].isStopped else {
                state.doubleStopCount += 1
                return
            }
            state.armed[index].isStopped = true
            state.stopCount += 1
        }
    }

    private final class Handle: FileWatchHandle, Sendable {
        let gateway: FakeFileWatchGateway
        let index: Int

        init(gateway: FakeFileWatchGateway, index: Int) {
            self.gateway = gateway
            self.index = index
        }

        func stop() { gateway.stop(index) }
    }
}
