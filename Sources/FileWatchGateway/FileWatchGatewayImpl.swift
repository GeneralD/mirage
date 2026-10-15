/// Live `FileWatchGateway`: a `DispatchSource` file-system object source over an event-only
/// file descriptor, shaped after lyra's `FileWatchGateway`. Wraps Dispatch and System.
/// Thin by rule: `FileDescriptor.open` throws for a path that cannot be watched, so there is
/// no branch here, and coalescing a burst of events is `EffectWatchDataSource`'s.
import Dispatch
import Domain
import System

public struct FileWatchGatewayImpl: FileWatchGateway {
    public init() {}

    /// A directory descriptor survives an editor's atomic save (the rename changes the entry) but
    /// never sees an in-place write to a file inside; the file descriptor is the reverse.
    public func watch(directory: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        try watchPath(directory, onChange: onChange)
    }

    public func watch(file: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        try watchPath(file, onChange: onChange)
    }

    private func watchPath(_ path: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        let descriptor = try FileDescriptor.open(FilePath(path), .readOnly, options: .eventOnly)
        // `.attrib` is load-bearing: shrinking a file with ftruncate posts only NOTE_ATTRIB, never
        // NOTE_WRITE, so a truncating in-place save would otherwise go unseen.
        let source = DispatchSource.makeFileSystemObjectSource(  // allow-physical: FileWatchGateway
            fileDescriptor: descriptor.rawValue, eventMask: [.write, .extend, .attrib, .delete, .rename], queue: .global())
        source.setEventHandler { onChange() }
        source.setCancelHandler { try? descriptor.close() }
        source.resume()
        return DispatchFileWatchHandle(source: source)
    }
}
