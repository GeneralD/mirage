import AVFoundationGateway
import AppDirectories
import BundledEffectDataSource
import CameraControlUseCase
import CameraDataSource
import CameraInteractor
import CameraPermissionDataSource
import CameraRepository
import CommonDependencyInjection
import Dependencies
import Domain
import EffectCatalogUseCase
import EffectInteractor
import EffectPackageDataSource
import EffectPackageRepository
import EffectRuntimeRepository
import EffectRuntimeStateDataSource
import EffectWatchDataSource
import ExtensionInstallDataSource
import ExtensionInstallRepository
import ExtensionInstallUseCase
import FileSystemGateway
import FileWatchGateway
import FramePipelineUseCase
import FrameTransportDataSource
import GPURenderDataSource
import HarnessInteractor
import MetalGateway
import MetalKitPreviewGateway
import PreferencesDataStore
import PreviewDataSource
import PreviewRepository
import SettingsRepository
import ShaderCompilationDataSource
import SystemExtensionGateway
import UserDefaultsGateway
import VirtualCameraRepository
import WorkspaceGateway

// Live values of the host process, on top of CommonDependencyInjection.

extension CameraInteractorKey: DependencyKey {
    public static let liveValue: any CameraInteractor = CameraInteractorImpl()
}

extension HarnessInteractorKey: DependencyKey {
    public static let liveValue: any HarnessInteractor = HarnessInteractorImpl()
}

extension EffectInteractorKey: DependencyKey {
    public static let liveValue: any EffectInteractor = EffectInteractorImpl()
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

extension EffectCatalogUseCaseKey: DependencyKey {
    public static let liveValue: any EffectCatalogUseCase = EffectCatalogUseCaseImpl()
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

extension EffectRuntimeRepositoryKey: DependencyKey {
    public static let liveValue: any EffectRuntimeRepository = EffectRuntimeRepositoryImpl()
}

extension PreviewSinkKey: DependencyKey {
    public static let liveValue: any PreviewSink = PreviewRepositoryImpl()
}

extension EffectPackageRepositoryKey: DependencyKey {
    public static let liveValue: any EffectPackageRepository = EffectPackageRepositoryImpl()
}

extension SettingsRepositoryKey: DependencyKey {
    public static let liveValue: any SettingsRepository = SettingsRepositoryImpl()
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

extension PreviewRendererKey: DependencyKey {
    public static let liveValue: any PreviewRenderer = PreviewDataSourceImpl()
}

extension CameraExtensionInstallerKey: DependencyKey {
    public static let liveValue: any CameraExtensionInstaller = ExtensionInstallDataSourceImpl()
}

extension BundledEffectsKey: DependencyKey {
    public static let liveValue: any BundledEffects = BundledEffectDataSourceImpl()
}

extension EffectRuntimeStateKey: DependencyKey {
    public static let liveValue: any EffectRuntimeState = EffectRuntimeStateDataSourceImpl()
}

extension ShaderCompilerKey: DependencyKey {
    public static let liveValue: any ShaderCompiler = ShaderCompilationDataSourceImpl()
}

extension GPURendererKey: DependencyKey {
    public static let liveValue: any GPURenderer = GPURenderDataSourceImpl()
}

extension EffectPackagesKey: DependencyKey {
    public static let liveValue: any EffectPackages = EffectPackageDataSourceImpl()
}

extension EffectWatchKey: DependencyKey {
    public static let liveValue: any EffectWatch = EffectWatchDataSourceImpl()
}

extension PreferencesKey: DependencyKey {
    public static let liveValue: any Preferences = PreferencesDataStoreImpl()
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

extension PreviewGatewayKey: DependencyKey {
    public static let liveValue: any PreviewGateway = MetalKitPreviewGatewayImpl()
}

extension FileSystemGatewayKey: DependencyKey {
    public static let liveValue: any FileSystemGateway = FileSystemGatewayImpl()
}

extension FileWatchGatewayKey: DependencyKey {
    public static let liveValue: any FileWatchGateway = FileWatchGatewayImpl()
}

extension WorkspaceGatewayKey: DependencyKey {
    public static let liveValue: any WorkspaceGateway = WorkspaceGatewayImpl()
}

extension AppDirectoriesProviderKey: DependencyKey {
    public static let liveValue: any AppDirectoriesProvider = AppDirectoriesProviderImpl()
}

extension KeyValueStoreGatewayKey: DependencyKey {
    public static let liveValue: any KeyValueStoreGateway = KeyValueStoreGatewayImpl()
}
