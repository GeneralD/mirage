// swift-tools-version: 6.0

import PackageDescription

// One SwiftPM target per layer slice (docs/ARCHITECTURE.md → Module Dependency
// Graph). Implementation targets depend on `Domain` only; the three DI targets
// are the only importers of implementation targets. Gateway modules are the
// sole importers of OS frameworks (`make check` → scripts/check-imports.sh).
//
// M0 built the pass-through frame path host → Camera Extension, the
// installer and the three DI targets; MVP-A added the effect runtime, the
// preview and the dev harness. MVP-B adds the `.lens` catalog: its seven modules
// (EffectPackageDataSource … EffectInteractor) start as pass-through defaults that
// the later MVP-B issues replace in place; the menu-bar UI lane (AppRouter, the
// Presenters) arrives with them.

let dependencies: [Target.Dependency] = [
    "Domain",
    .product(name: "Dependencies", package: "swift-dependencies"),
]

let testDependencies: [Target.Dependency] = [
    "TestSupport",
    "TestDoubles",
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "Clocks", package: "swift-clocks"),
]

/// A layer-slice implementation target plus its test target.
func slice(_ name: String, extraTests: [Target.Dependency] = []) -> [Target] {
    [
        .target(name: name, dependencies: dependencies),
        .testTarget(name: "\(name)Tests", dependencies: [.target(name: name)] + testDependencies + extraTests),
    ]
}

/// A Gateway / Support live target. CI-unreachable Gateways get no test target
/// here; the ones that can run anywhere get a smoke suite.
func live(_ name: String, smoke: Bool) -> [Target] {
    let target = Target.target(name: name, dependencies: dependencies)
    guard smoke else { return [target] }
    return [target, .testTarget(name: "\(name)Tests", dependencies: [.target(name: name)] + testDependencies)]
}

let package = Package(
    name: "VirtualCamera",
    platforms: [.macOS(.v14)],
    products: [
        // Linked by the xcodegen shells (project.yml): the host `.app` and the
        // Camera Extension bundle. Each shell's main.swift calls one entry point.
        .library(name: "App", targets: ["App"]),
        .library(name: "ExtensionApp", targets: ["ExtensionApp"]),
        // `swift run dev-harness`: camera prompt + preview window, no extension.
        // Not shipped (no xcodegen shell links it); `make build-dev-harness` builds it.
        .executable(name: "dev-harness", targets: ["DevHarness"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
    ],
    targets: [
        // ── Contract / Model ──
        .target(name: "Entity"),
        .testTarget(name: "EntityTests", dependencies: ["Entity", "TestSupport"]),
        .target(
            name: "Domain",
            dependencies: [
                "Entity",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── Provider / Support ──
        .target(name: "HostTime", dependencies: dependencies),
        .testTarget(name: "HostTimeTests", dependencies: ["HostTime"] + testDependencies),
        .target(name: "UnifiedLog", dependencies: dependencies),
        .testTarget(name: "UnifiedLogTests", dependencies: ["UnifiedLog"] + testDependencies),
        // Host only: the effects folder's path under Application Support. Builds a path, reads no environment variable.
        .target(name: "AppDirectories", dependencies: dependencies),
        .testTarget(name: "AppDirectoriesTests", dependencies: ["AppDirectories"] + testDependencies),

        // ── Gateway (OS boundary) ──
        .target(name: "AVFoundationGateway", dependencies: dependencies),
        .target(name: "IOSurfaceGateway", dependencies: dependencies),
        .testTarget(name: "IOSurfaceGatewayTests", dependencies: ["IOSurfaceGateway"] + testDependencies),
        // Host only: never a dependency of ExtensionDependencyInjection / ExtensionApp
        // (scripts/check-extension-no-metal.sh). Exercised by GPUSmokeTests, not here.
        .target(name: "MetalGateway", dependencies: dependencies),
        // Host only, like MetalGateway. Exercised by PreviewSmokeTests (GPUSmokeTests).
        .target(name: "MetalKitPreviewGateway", dependencies: dependencies),
        .target(name: "MachGateway", dependencies: dependencies),
        .testTarget(name: "MachGatewayTests", dependencies: ["MachGateway", "IOSurfaceGateway"] + testDependencies),
        .target(name: "SystemExtensionGateway", dependencies: dependencies),
        .target(name: "CMIOExtensionGateway", dependencies: dependencies),
        .target(name: "DispatchExecutorGateway", dependencies: dependencies),
        .testTarget(name: "DispatchExecutorGatewayTests", dependencies: ["DispatchExecutorGateway"] + testDependencies),
        // Host only (with FileWatchGateway, WorkspaceGateway and AppDirectories): the effects folder's
        // file system. Smoke under a UUID temp directory; nothing above resolves it until EffectPackageDataSource.
        .target(name: "FileSystemGateway", dependencies: dependencies),
        .testTarget(name: "FileSystemGatewayTests", dependencies: ["FileSystemGateway"] + testDependencies),
        // Host only: DispatchSource file-system object sources over event-only descriptors. Smoke under a UUID temp directory.
        .target(name: "FileWatchGateway", dependencies: dependencies),
        .testTarget(name: "FileWatchGatewayTests", dependencies: ["FileWatchGateway"] + testDependencies),
        // Host only: Finder through NSWorkspace. Coverage-ignored and thin (scripts/check-live-thin.sh); no smoke, CI must not open Finder.
        .target(name: "WorkspaceGateway", dependencies: dependencies),

        // ── DataSource ──
        .target(name: "CameraDataSource", dependencies: dependencies),
        .testTarget(name: "CameraDataSourceTests", dependencies: ["CameraDataSource"] + testDependencies),
        .target(name: "CameraPermissionDataSource", dependencies: dependencies),
        .testTarget(name: "CameraPermissionDataSourceTests", dependencies: ["CameraPermissionDataSource"] + testDependencies),
        .target(name: "SurfacePoolDataSource", dependencies: dependencies),
        .testTarget(name: "SurfacePoolDataSourceTests", dependencies: ["SurfacePoolDataSource"] + testDependencies),
        .target(name: "FrameTransportDataSource", dependencies: dependencies),
        .testTarget(name: "FrameTransportDataSourceTests", dependencies: ["FrameTransportDataSource"] + testDependencies),
        .target(name: "FrameReceiverDataSource", dependencies: dependencies),
        .testTarget(name: "FrameReceiverDataSourceTests", dependencies: ["FrameReceiverDataSource"] + testDependencies),
        .target(name: "StreamOutputDataSource", dependencies: dependencies),
        .testTarget(name: "StreamOutputDataSourceTests", dependencies: ["StreamOutputDataSource"] + testDependencies),
        .target(name: "ExtensionInstallDataSource", dependencies: dependencies),
        .testTarget(name: "ExtensionInstallDataSourceTests", dependencies: ["ExtensionInstallDataSource"] + testDependencies),
        // Host only: the prelude, `#line` assembly, diagnostic mapping and the off-main compile.
        .target(name: "ShaderCompilationDataSource", dependencies: dependencies),
        .testTarget(name: "ShaderCompilationDataSourceTests", dependencies: ["ShaderCompilationDataSource"] + testDependencies),
        // Host only: the bundled effect's MSL as a string constant (epic #14, D1).
        .target(name: "BundledEffectDataSource", dependencies: dependencies),
        .testTarget(name: "BundledEffectDataSourceTests", dependencies: ["BundledEffectDataSource"] + testDependencies),
        // Host only: the effect runtime's executor-confined memory (compile cache, selection, tickets, session clock).
        .target(name: "EffectRuntimeStateDataSource", dependencies: dependencies),
        .testTarget(name: "EffectRuntimeStateDataSourceTests", dependencies: ["EffectRuntimeStateDataSource"] + testDependencies),
        // Host only (it drives MetalGateway through the GPU ports): one effect pass, one command buffer.
        .target(name: "GPURenderDataSource", dependencies: dependencies),
        .testTarget(name: "GPURenderDataSourceTests", dependencies: ["GPURenderDataSource"] + testDependencies),
        // Host only: the preview kernel and the draw order (scripts/check-extension-no-metal.sh).
        .target(name: "PreviewDataSource", dependencies: dependencies),
        .testTarget(name: "PreviewDataSourceTests", dependencies: ["PreviewDataSource"] + testDependencies),
        // Host only: the effects folder's `.lens` packages. Holds the pass-through `NoPackages` until
        // the real DataSource lands in this module (epic #42, D10).
        .target(name: "EffectPackageDataSource", dependencies: dependencies),
        .testTarget(name: "EffectPackageDataSourceTests", dependencies: ["EffectPackageDataSource"] + testDependencies),
        // Host only: file events folded into one change per burst. Holds `NeverChangingWatch` for now.
        .target(name: "EffectWatchDataSource", dependencies: dependencies),
        .testTarget(name: "EffectWatchDataSourceTests", dependencies: ["EffectWatchDataSource"] + testDependencies),

        // ── DataStore ──
        // Host only: the chosen effect, kept between launches. Holds `EmptyPreferences` for now.
        .target(name: "PreferencesDataStore", dependencies: dependencies),
        .testTarget(name: "PreferencesDataStoreTests", dependencies: ["PreferencesDataStore"] + testDependencies),

        // ── Repository ──
        .target(name: "CameraRepository", dependencies: dependencies),
        .testTarget(name: "CameraRepositoryTests", dependencies: ["CameraRepository"] + testDependencies),
        .target(name: "VirtualCameraRepository", dependencies: dependencies),
        .testTarget(name: "VirtualCameraRepositoryTests", dependencies: ["VirtualCameraRepository"] + testDependencies),
        .target(name: "SurfaceRepository", dependencies: dependencies),
        .testTarget(name: "SurfaceRepositoryTests", dependencies: ["SurfaceRepository"] + testDependencies),
        .target(name: "FrameReceiverRepository", dependencies: dependencies),
        .testTarget(name: "FrameReceiverRepositoryTests", dependencies: ["FrameReceiverRepository"] + testDependencies),
        .target(name: "StreamOutputRepository", dependencies: dependencies),
        .testTarget(name: "StreamOutputRepositoryTests", dependencies: ["StreamOutputRepository"] + testDependencies),
        .target(name: "ExtensionInstallRepository", dependencies: dependencies),
        .testTarget(name: "ExtensionInstallRepositoryTests", dependencies: ["ExtensionInstallRepository"] + testDependencies),
        // Host only: orchestrates the compile, the runtime's state and the render pass; holds no state.
        .target(name: "EffectRuntimeRepository", dependencies: dependencies),
        .testTarget(
            name: "EffectRuntimeRepositoryTests", dependencies: ["EffectRuntimeRepository", "EffectRuntimeStateDataSource"] + testDependencies),
        .target(name: "PreviewRepository", dependencies: dependencies),
        .testTarget(name: "PreviewRepositoryTests", dependencies: ["PreviewRepository"] + testDependencies),
        // Host only: the bundled effects and the packages as one catalog, listed again after every change.
        .target(name: "EffectPackageRepository", dependencies: dependencies),
        .testTarget(name: "EffectPackageRepositoryTests", dependencies: ["EffectPackageRepository"] + testDependencies),
        // Host only: the chosen effect as the UseCases see it. Holds `EmptySettings` for now.
        .target(name: "SettingsRepository", dependencies: dependencies),
        .testTarget(name: "SettingsRepositoryTests", dependencies: ["SettingsRepository"] + testDependencies),

        // ── UseCase ──
        .target(name: "FramePipelineUseCase", dependencies: dependencies),
        .testTarget(name: "FramePipelineUseCaseTests", dependencies: ["FramePipelineUseCase"] + testDependencies),
        .target(name: "CameraControlUseCase", dependencies: dependencies),
        .testTarget(name: "CameraControlUseCaseTests", dependencies: ["CameraControlUseCase"] + testDependencies),
        .target(name: "ExtensionInstallUseCase", dependencies: dependencies),
        .testTarget(name: "ExtensionInstallUseCaseTests", dependencies: ["ExtensionInstallUseCase"] + testDependencies),
        .target(name: "ExtensionRelayUseCase", dependencies: dependencies),
        .testTarget(name: "ExtensionRelayUseCaseTests", dependencies: ["ExtensionRelayUseCase"] + testDependencies),
        // Host only: the effects menu's policy (selection, hot reload, fallback). Holds `BundledOnlyEffectCatalog` for now.
        .target(name: "EffectCatalogUseCase", dependencies: dependencies),
        .testTarget(name: "EffectCatalogUseCaseTests", dependencies: ["EffectCatalogUseCase"] + testDependencies),

        // ── Interactor ──
        .target(name: "CameraInteractor", dependencies: dependencies),
        .testTarget(name: "CameraInteractorTests", dependencies: ["CameraInteractor"] + testDependencies),
        // Host only: the dev harness's launch sequence (camera prompt, then the pipeline).
        .target(name: "HarnessInteractor", dependencies: dependencies),
        .testTarget(name: "HarnessInteractorTests", dependencies: ["HarnessInteractor"] + testDependencies),
        // Host only: the effects menu's Combine pipeline. Holds `StaticEffectInteractor` for now.
        .target(name: "EffectInteractor", dependencies: dependencies),
        .testTarget(name: "EffectInteractorTests", dependencies: ["EffectInteractor"] + testDependencies),

        // ── DependencyInjection (liveValue registrations, and dev-only substitutions that only assign one value) ──
        .target(
            name: "CommonDependencyInjection",
            dependencies: dependencies + [
                "SurfaceRepository", "SurfacePoolDataSource", "IOSurfaceGateway", "MachGateway", "UnifiedLog", "HostTime",
                "DispatchExecutorGateway",
            ]
        ),
        .target(
            name: "HostDependencyInjection",
            dependencies: dependencies + [
                "CommonDependencyInjection",
                "CameraInteractor", "HarnessInteractor", "EffectInteractor",
                "FramePipelineUseCase", "CameraControlUseCase", "ExtensionInstallUseCase", "EffectCatalogUseCase",
                "CameraRepository", "VirtualCameraRepository", "ExtensionInstallRepository",
                "EffectRuntimeRepository", "PreviewRepository", "EffectPackageRepository", "SettingsRepository",
                "CameraDataSource", "CameraPermissionDataSource", "FrameTransportDataSource", "ExtensionInstallDataSource",
                "BundledEffectDataSource", "EffectRuntimeStateDataSource", "ShaderCompilationDataSource", "GPURenderDataSource",
                "PreviewDataSource", "EffectPackageDataSource", "EffectWatchDataSource", "PreferencesDataStore",
                "AVFoundationGateway", "MetalGateway", "MetalKitPreviewGateway", "SystemExtensionGateway",
                "FileSystemGateway", "FileWatchGateway", "WorkspaceGateway", "AppDirectories",
            ]
        ),
        .testTarget(
            name: "HostDependencyInjectionTests",
            dependencies: [
                "HostDependencyInjection", "EffectInteractor", "EffectCatalogUseCase", "EffectPackageRepository", "SettingsRepository",
                "EffectPackageDataSource", "EffectWatchDataSource", "PreferencesDataStore",
                "FileSystemGateway", "FileWatchGateway", "WorkspaceGateway", "AppDirectories",
            ] + testDependencies
        ),
        .target(
            name: "ExtensionDependencyInjection",
            dependencies: dependencies + [
                "CommonDependencyInjection",
                "ExtensionRelayUseCase",
                "FrameReceiverRepository", "StreamOutputRepository",
                "FrameReceiverDataSource", "StreamOutputDataSource",
                "CMIOExtensionGateway",
            ]
        ),

        // ── View (declarative, coverage-ignored, no test target; host only) ──
        .target(name: "Views", dependencies: dependencies),

        // ── Entry ──
        .target(name: "App", dependencies: dependencies + ["HostDependencyInjection"]),
        .target(name: "ExtensionApp", dependencies: dependencies + ["ExtensionDependencyInjection"]),
        // The development harness (host graph only). `main.swift` launches AppKit;
        // HarnessSession holds its lifecycle and wiring (DevHarnessTests); what it does
        // is HarnessInteractor's, over CameraControlUseCase and FramePipelineUseCase.
        // A SwiftPM executable has no bundle, so its Info.plist (bundle id, camera
        // usage string for TCC) is linked in as the __TEXT,__info_plist section —
        // the one hand-written plist, outside the xcodegen shells (docs/ARCHITECTURE.md
        // → Key Design Decisions). `unsafeFlags` is accepted in a root package only,
        // and no shipped product contains this target. The path is absolute so the
        // link does not depend on the directory `swift` runs from.
        .executableTarget(
            name: "DevHarness",
            dependencies: dependencies + ["HostDependencyInjection", "Views"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(Context.packageDirectory)/Tools/DevHarness/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "DevHarnessTests",
            dependencies: ["DevHarness", "FramePipelineUseCase", "HarnessInteractor", "HostDependencyInjection", "VirtualCameraRepository"]
                + testDependencies
        ),

        // ── GPU smoke (own process via `make test-gpu`; never in the coverage run) ──
        // Imports Metal and IOSurface directly: a test target, not a Gateway, so the
        // import allow-list (Sources/ only) does not apply. .claude/rules/gpu-testing.md.
        .testTarget(
            name: "GPUSmokeTests",
            dependencies: dependencies + [
                "MetalGateway", "MetalKitPreviewGateway", "IOSurfaceGateway", "ShaderCompilationDataSource", "GPURenderDataSource",
                "BundledEffectDataSource", "EffectRuntimeRepository", "EffectRuntimeStateDataSource", "PreviewDataSource", "Views",
                "TestDoubles", "TestSupport",
            ]
        ),

        // ── Test support ──
        .target(
            name: "TestSupport",
            dependencies: [],
            path: "Tests/TestSupport"
        ),
        .target(
            name: "TestDoubles",
            dependencies: dependencies + ["TestSupport", .product(name: "Clocks", package: "swift-clocks")],
            path: "Tests/TestDoubles"
        ),
        .testTarget(name: "TestSupportTests", dependencies: ["TestSupport", "TestDoubles"]),
        // Contract tests of the fakes themselves: manual completion, ordering,
        // provenance and the counters the DataSource suites rely on.
        .testTarget(name: "TestDoublesTests", dependencies: testDependencies),

        // ── Integration (host → in-memory loopback → extension) ──
        .testTarget(
            name: "FramePathIntegrationTests",
            dependencies: testDependencies + [
                "FramePipelineUseCase", "CameraRepository", "VirtualCameraRepository", "SurfaceRepository",
                "SurfacePoolDataSource", "CameraDataSource", "FrameTransportDataSource",
                "ExtensionRelayUseCase", "FrameReceiverRepository", "StreamOutputRepository",
                "FrameReceiverDataSource", "StreamOutputDataSource", "PreviewRepository", "PreviewDataSource",
                "EffectRuntimeRepository", "EffectRuntimeStateDataSource", "ShaderCompilationDataSource", "GPURenderDataSource",
                "BundledEffectDataSource",
            ]
        ),
    ]
)
