import CMIOExtensionGateway
import CommonDependencyInjection
import Dependencies
import Domain
import ExtensionRelayUseCase
import FrameReceiverDataSource
import FrameReceiverRepository
import StreamOutputDataSource
import StreamOutputRepository

// Live values of the Camera Extension process, on top of CommonDependencyInjection.

extension ExtensionRelayUseCaseKey: DependencyKey {
    public static let liveValue: any ExtensionRelayUseCase = ExtensionRelayUseCaseImpl()
}

extension FrameReceiverRepositoryKey: DependencyKey {
    public static let liveValue: any FrameReceiverRepository = FrameReceiverRepositoryImpl()
}

extension StreamOutputRepositoryKey: DependencyKey {
    public static let liveValue: any StreamOutputRepository = StreamOutputRepositoryImpl()
}

extension FrameReceiverKey: DependencyKey {
    public static let liveValue: any FrameReceiver = FrameReceiverDataSourceImpl()
}

extension StreamOutputKey: DependencyKey {
    public static let liveValue: any StreamOutput = StreamOutputDataSourceImpl()
}

extension StreamOutputGatewayKey: DependencyKey {
    public static let liveValue: any StreamOutputGateway = StreamOutputGatewayImpl()
}
