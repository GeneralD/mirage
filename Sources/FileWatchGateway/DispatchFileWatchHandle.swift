import Dispatch
import Domain

/// One armed watch: owns the live source and cancels it exactly once through `stop()`, which
/// also closes the descriptor (the source's cancel handler). A class because the handle is
/// the source's identity; `@unchecked Sendable` because a dispatch source is itself safe to
/// cancel from any thread and the handle holds nothing else.
final class DispatchFileWatchHandle: FileWatchHandle, @unchecked Sendable {
    private let source: any DispatchSourceFileSystemObject

    init(source: any DispatchSourceFileSystemObject) {
        self.source = source
    }

    func stop() {
        source.cancel()
    }
}
