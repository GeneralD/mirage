import AVFoundationGateway
import CameraControlUseCase
import CameraDataSource
import CameraInteractor
import CameraPermissionDataSource
import CameraRepository
import CommonDependencyInjection
import Dependencies
import Domain
import EffectRuntimeRepository
import ExtensionInstallDataSource
import ExtensionInstallRepository
import ExtensionInstallUseCase
import FramePipelineUseCase
import FrameTransportDataSource
import GPURenderDataSource
import MetalGateway
import PreviewRepository
import SystemExtensionGateway
import VirtualCameraRepository

// Live values of the host process, on top of CommonDependencyInjection.

extension CameraInteractorKey: DependencyKey {
    public static let liveValue: any CameraInteractor = CameraInteractorImpl()
}

extension FramePipelineUseCaseKey: DependencyKey {
    public static let liveValue: any FramePipelineUseCase = FramePipelineUseCaseImpl()
}

extension CameraControlUseCaseKey: DependencyKey {
    public static let liveValue: any CameraControlUseCase = CameraControlUseCaseImpl()
}

extension ExtensionInstallUseCaseKey: DependencyKey {
    public static let liveValue: any ExtensionInstallUseCase = ExtensionInstallUseCaseImpl()
}

extension CameraRepositoryKey: DependencyKey {
    public static let liveValue: any CameraRepository = CameraRepositoryImpl()
}

extension VirtualCameraSinkKey: DependencyKey {
    public static let liveValue: any VirtualCameraSink = VirtualCameraRepositoryImpl()
}

extension ExtensionInstallRepositoryKey: DependencyKey {
    public static let liveValue: any ExtensionInstallRepository = ExtensionInstallRepositoryImpl()
}

// Pass-through defaults (epic #14, D18): replaced in place by #19 and #20.
extension EffectRuntimeRepositoryKey: DependencyKey {
    public static let liveValue: any EffectRuntimeRepository = PassthroughEffectRuntimeRepository()
}

extension PreviewSinkKey: DependencyKey {
    public static let liveValue: any PreviewSink = DiscardingPreviewSink()
}

extension CameraSourceKey: DependencyKey {
    public static let liveValue: any CameraSource = CameraDataSourceImpl()
}

extension CameraPermissionKey: DependencyKey {
    public static let liveValue: any CameraPermission = CameraPermissionDataSourceImpl()
}

extension FrameTransportKey: DependencyKey {
    public static let liveValue: any FrameTransport = FrameTransportDataSourceImpl()
}

extension CameraExtensionInstallerKey: DependencyKey {
    public static let liveValue: any CameraExtensionInstaller = ExtensionInstallDataSourceImpl()
}

extension GPURendererKey: DependencyKey {
    public static let liveValue: any GPURenderer = GPURenderDataSourceImpl()
}

extension CaptureSessionGatewayKey: DependencyKey {
    public static let liveValue: any CaptureSessionGateway = CaptureSessionGatewayImpl()
}

extension CameraAuthorizationGatewayKey: DependencyKey {
    public static let liveValue: any CameraAuthorizationGateway = CameraAuthorizationGatewayImpl()
}

extension SystemExtensionGatewayKey: DependencyKey {
    public static let liveValue: any SystemExtensionGateway = SystemExtensionGatewayImpl()
}

extension GPUGatewayKey: DependencyKey {
    public static let liveValue: any GPUGateway = MetalGatewayImpl()
}

extension ShaderLibraryGatewayKey: DependencyKey {
    public static let liveValue: any ShaderLibraryGateway = MetalGatewayImpl()
}

extension TextureCacheGatewayKey: DependencyKey {
    public static let liveValue: any TextureCacheGateway = MetalGatewayImpl()
}
