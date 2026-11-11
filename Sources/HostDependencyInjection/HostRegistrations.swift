import AVFoundationGateway
import AppDirectories
import BundledEffectDataSource
import CameraControlUseCase
import CameraDataSource
import CameraInteractor
import CameraPermissionDataSource
import CameraRepository
import CommonDependencyInjection
import ControlsInteractor
import Dependencies
import Domain
import EffectAuthoringInteractor
import EffectAuthoringUseCase
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
import HotkeyDataSource
import HotkeyGateway
import LoginItemDataSource
import LoginItemGateway
import MetalGateway
import MetalKitPreviewGateway
import PreferencesDataStore
import PreviewDataSource
import PreviewRepository
import SettingsInteractor
import SettingsRepository
import SettingsUseCase
import ShaderCompilationDataSource
import StandardStreams
import StillImageDataSource
import StillImageRepository
import StoreMaintenanceDataStore
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

extension PreviewInteractorKey: DependencyKey {
    public static let liveValue: any PreviewInteractor = PreviewInteractorImpl()
}

extension EffectInteractorKey: DependencyKey {
    public static let liveValue: any EffectInteractor = EffectInteractorImpl()
}

extension CameraSelectionInteractorKey: DependencyKey {
    public static let liveValue: any CameraSelectionInteractor = CameraSelectionInteractorImpl()
}

extension ControlsInteractorKey: DependencyKey {
    public static let liveValue: any ControlsInteractor = ControlsInteractorImpl()
}

extension SettingsInteractorKey: DependencyKey {
    public static let liveValue: any SettingsInteractor = SettingsInteractorImpl()
}

extension FramePipelineUseCaseKey: DependencyKey {
    public static let liveValue: any FramePipelineUseCase = FramePipelineUseCaseImpl()
}

extension CameraControlUseCaseKey: DependencyKey {
    public static let liveValue: any CameraControlUseCase = CameraControlUseCaseImpl()
}

extension CameraSelectionUseCaseKey: DependencyKey {
    public static let liveValue: any CameraSelectionUseCase = CameraSelectionUseCaseImpl()
}

extension ExtensionInstallUseCaseKey: DependencyKey {
    public static let liveValue: any ExtensionInstallUseCase = ExtensionInstallUseCaseImpl()
}

extension EffectCatalogUseCaseKey: DependencyKey {
    public static let liveValue: any EffectCatalogUseCase = EffectCatalogUseCaseImpl()
}

extension EffectAuthoringUseCaseKey: DependencyKey {
    public static let liveValue: any EffectAuthoringUseCase = EffectAuthoringUseCaseImpl()
}

extension SettingsUseCaseKey: DependencyKey {
    public static let liveValue: any SettingsUseCase = SettingsUseCaseImpl()
}

extension CameraRepositoryKey: DependencyKey {
    public static let liveValue: any CameraRepository = CameraRepositoryImpl()
}

extension CameraSelectionRepositoryKey: DependencyKey {
    public static let liveValue: any CameraSelectionRepository = CameraSelectionRepositoryImpl()
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

extension CameraDevicesKey: DependencyKey {
    public static let liveValue: any CameraDevices = CameraDevicesDataSourceImpl()
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

extension CameraPreferencesKey: DependencyKey {
    public static let liveValue: any CameraPreferences = CameraPreferencesDataStoreImpl()
}

extension StoreMaintenanceKey: DependencyKey {
    public static let liveValue: any StoreMaintenance = StoreMaintenanceDataStoreImpl()
}

extension HotkeysKey: DependencyKey {
    public static let liveValue: any Hotkeys = HotkeyDataSourceImpl()
}

extension LoginItemKey: DependencyKey {
    public static let liveValue: any LoginItem = LoginItemDataSourceImpl()
}

extension CaptureSessionGatewayKey: DependencyKey {
    public static let liveValue: any CaptureSessionGateway = CaptureSessionGatewayImpl()
}

extension CameraDeviceGatewayKey: DependencyKey {
    public static let liveValue: any CameraDeviceGateway = CameraDeviceGatewayImpl()
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

extension HotkeyGatewayKey: DependencyKey {
    public static let liveValue: any HotkeyGateway = HotkeyGatewayImpl()
}

extension LoginItemGatewayKey: DependencyKey {
    public static let liveValue: any LoginItemGateway = LoginItemGatewayImpl()
}

extension StillImagesKey: DependencyKey {
    public static let liveValue: any StillImages = StillImageDataSourceImpl()
}

extension StillImageRepositoryKey: DependencyKey {
    public static let liveValue: any StillImageRepository = StillImageRepositoryImpl()
}

extension ConsoleWriterKey: DependencyKey {
    public static let liveValue: any ConsoleWriter = StandardStreamsImpl()
extension EffectAuthoringInteractorKey: DependencyKey {
    public static let liveValue: any EffectAuthoringInteractor = EffectAuthoringInteractorImpl()
}
