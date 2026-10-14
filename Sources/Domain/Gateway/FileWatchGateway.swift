import Dependencies

/// Thin pass-through to the kernel's file events (live: `DispatchSource` file-system
/// object sources, copied from lyra's `ConfigWatchGateway`; epic #42, D4). Two
/// watches because neither alone sees every way an editor saves:
/// - a **directory** watch survives an atomic save (the rename changes the directory
///   entry) but never fires for an in-place write to a file inside it;
/// - a **file** watch sees an in-place overwrite but dies on a rename, so the caller
///   arms it again after every listing.
///
/// `onChange` may run on any thread, any number of times, in bursts; it does nothing
/// but report. Coalescing a burst is `EffectWatchDataSource`'s, on the injected clock.
/// A path that cannot be watched (it does not exist) throws.
public protocol FileWatchGateway: Sendable {
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle
    func watch(file: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle
}

/// One armed watch. Its owner stops it exactly once; after `stop()` `onChange` never runs again.
public protocol FileWatchHandle: Sendable {
    func stop()
}

public enum FileWatchGatewayKey: TestDependencyKey {
    public static let testValue: any FileWatchGateway = UnimplementedFileWatchGateway()
}

extension DependencyValues {
    public var fileWatchGateway: any FileWatchGateway {
        get { self[FileWatchGatewayKey.self] }
        set { self[FileWatchGatewayKey.self] = newValue }
    }
}

private struct UnimplementedFileWatchGateway: FileWatchGateway {
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        reportIssue("FileWatchGateway.watch(directory:) not implemented")
        return UnimplementedFileWatchHandle()
    }

    func watch(file: String, onChange: @escaping @Sendable () -> Void) throws -> any FileWatchHandle {
        reportIssue("FileWatchGateway.watch(file:) not implemented")
        return UnimplementedFileWatchHandle()
    }
}

private struct UnimplementedFileWatchHandle: FileWatchHandle {
    func stop() {}
}
