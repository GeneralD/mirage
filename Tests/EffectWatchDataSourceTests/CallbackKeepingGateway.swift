import Domain
import TestDoubles

/// The `FileWatchGateway` that `WatchRig` hands the subject: every call goes to the fake, and the
/// `onChange` of each watch that was armed is kept as well.
///
/// The fake never fires a stopped watch, as the port promises. A dispatch source, though, cannot
/// recall a callback that is already running when `cancel()` returns, so an event can still reach
/// the subject after its stream has ended. `callbacks` is how a test delivers one: it holds what
/// the subject handed over, whatever has happened to the watch since.
final class CallbackKeepingGateway: FileWatchGateway, Sendable {
    private let inner: FakeFileWatchGateway
    private let kept = Locked<[@Sendable () -> Void]>([])

    init(wrapping inner: FakeFileWatchGateway) {
        self.inner = inner
    }

    /// Every `onChange` of a watch that was armed, in arming order. A watch that threw is not here.
    var callbacks: [@Sendable () -> Void] { kept.current }

    func watch(directory: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        let handle = try inner.watch(directory: directory, onChange: onChange)
        kept.withLock { $0.append(onChange) }
        return handle
    }

    func watch(file: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        let handle = try inner.watch(file: file, onChange: onChange)
        kept.withLock { $0.append(onChange) }
        return handle
    }
}
