import Domain
import TestSupport

/// Scripted install flow: `install()` replays the scripted statuses in order
/// and leaves `status` at the last one. Used for both the data source and the
/// repository port, which share a shape.
public final class FakeCameraExtensionInstaller: CameraExtensionInstaller, ExtensionInstallRepository, Sendable {
    private let current: Locked<InstallStatus>
    private let script: Locked<[InstallStatus]>
    // Consumers of `updates()`, fed by every status `install()` yields; this double never finishes them.
    private let watchers: Locked<[AsyncStream<InstallStatus>.Continuation]>
    public let installs = Collector<Void>()

    public init(status: InstallStatus = .notInstalled, script: [InstallStatus] = [.installing, .installed]) {
        current = Locked(status)
        self.script = Locked(script)
        watchers = Locked([])
    }

    public var status: InstallStatus { current.current }

    public func scriptInstall(_ statuses: [InstallStatus]) {
        script.set(statuses)
    }

    public func install() async -> AsyncStream<InstallStatus> {
        installs.append(())
        let statuses = script.current
        return AsyncStream { continuation in
            for status in statuses {
                current.set(status)
                continuation.yield(status)
                for watcher in watchers.current { watcher.yield(status) }
            }
            continuation.finish()
        }
    }

    /// The current status first, then every status `install()` yields, until `finishUpdates()`.
    public func updates() async -> AsyncStream<InstallStatus> {
        let (stream, continuation) = AsyncStream<InstallStatus>.makeStream()
        watchers.withLock { list in
            continuation.yield(current.current)
            list.append(continuation)
        }
        return stream
    }

    public func finishUpdates() {
        watchers.withLock { list in
            for watcher in list { watcher.finish() }
            list = []
        }
    }
}

/// `SurfaceRepository` backed by a `FakeSurfacePool`, exposing the pool so a
/// test can hand out tokens and check the live count.
public final class FakeSurfaceRepository: SurfaceRepository, Sendable {
    public let pool: FakeSurfacePool

    public init(pool: FakeSurfacePool = FakeSurfacePool()) {
        self.pool = pool
    }

    public var liveCount: Int { pool.liveCount }

    public func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken? {
        try pool.allocate(descriptor)
    }

    public func allocate(_ descriptor: SurfaceDescriptor, filledWith byte: UInt8) throws -> SurfaceToken? {
        try pool.allocate(descriptor, filledWith: byte)
    }

    @discardableResult
    public func release(_ token: SurfaceToken) -> Bool {
        pool.release(token)
    }

    public func releaseAll() {
        pool.releaseAll()
    }

    /// Mints a leased frame for a test to feed into a subject.
    public func frame(descriptor: SurfaceDescriptor = .hd720, at time: HostTimestamp) -> FrameRef? {
        pool.adopt(FakeSurfaceHandle(id: UInt32(pool.liveCount + 1), descriptor: descriptor), descriptor: descriptor)
            .map { FrameRef(token: $0, descriptor: descriptor, presentationTime: time) }
    }
}
