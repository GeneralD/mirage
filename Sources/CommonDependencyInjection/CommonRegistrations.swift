import Dependencies
import DispatchExecutorGateway
import Domain
import HostTime
import IOSurfaceGateway
import MachGateway
import SurfacePoolDataSource
import SurfaceRepository
import UnifiedLog

// Live values shared by the host and the extension process. Each process has
// its own surface pool and its own frame executor; the scheduler shares the
// executor's queue so ticks run on the frame path.

private let liveFrameExecutor = FrameExecutorImpl()

extension FrameExecutorKey: DependencyKey {
    public static let liveValue: any FrameExecutor = liveFrameExecutor
}

extension FrameSchedulerKey: DependencyKey {
    public static let liveValue: any FrameScheduler = FrameSchedulerImpl(queue: liveFrameExecutor.queue)
}

extension HostTimeProviderKey: DependencyKey {
    public static let liveValue: any HostTimeProvider = HostTimeProviderImpl()
}

extension ErrorLogKey: DependencyKey {
    public static let liveValue: any ErrorLog = UnifiedLogImpl(level: .error)
}

extension DeveloperLogKey: DependencyKey {
    public static let liveValue: any DeveloperLog = UnifiedLogImpl(level: .debug)
}

extension IOSurfaceGatewayKey: DependencyKey {
    public static let liveValue: any IOSurfaceGateway = IOSurfaceGatewayImpl()
}

extension MachBootstrapGatewayKey: DependencyKey {
    public static let liveValue: any MachBootstrapGateway = MachBootstrapGatewayImpl()
}

extension MachMessageGatewayKey: DependencyKey {
    public static let liveValue: any MachMessageGateway = MachMessageGatewayImpl()
}

extension SurfacePoolKey: DependencyKey {
    public static let liveValue: any SurfacePool = SurfacePoolDataSourceImpl()
}

extension SurfaceRepositoryKey: DependencyKey {
    public static let liveValue: any SurfaceRepository = SurfaceRepositoryImpl()
}
