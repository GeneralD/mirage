// swift-tools-version: 6.0

import PackageDescription

// One SwiftPM target per layer slice (docs/ARCHITECTURE.md → Module Dependency
// Graph). Implementation targets depend on `Domain` only; the three DI targets
// are the only importers of implementation targets. Gateway modules are the
// sole importers of OS frameworks (`make check` → scripts/check-imports.sh).
//
// M0 scope: the pass-through frame path host → Camera Extension, the
// installer, and the three DI targets. Effects, preview and the GUI lane
// arrive with MVP-A.

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
        // Host only (it drives MetalGateway through the GPU ports): one effect pass, one command buffer.
        .target(name: "GPURenderDataSource", dependencies: dependencies),
        .testTarget(name: "GPURenderDataSourceTests", dependencies: ["GPURenderDataSource"] + testDependencies),
        // Host only: the preview kernel and the draw order (scripts/check-extension-no-metal.sh).
        .target(name: "PreviewDataSource", dependencies: dependencies),
        .testTarget(name: "PreviewDataSourceTests", dependencies: ["PreviewDataSource"] + testDependencies),

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
        // Host only. EffectRuntimeRepository ships a pass-through live value until #19
        // adds the real runtime to the same module (epic #14, D18).
        .target(name: "EffectRuntimeRepository", dependencies: dependencies),
        .testTarget(name: "EffectRuntimeRepositoryTests", dependencies: ["EffectRuntimeRepository"] + testDependencies),
        .target(name: "PreviewRepository", dependencies: dependencies),
        .testTarget(name: "PreviewRepositoryTests", dependencies: ["PreviewRepository"] + testDependencies),

        // ── UseCase ──
        .target(name: "FramePipelineUseCase", dependencies: dependencies),
        .testTarget(name: "FramePipelineUseCaseTests", dependencies: ["FramePipelineUseCase"] + testDependencies),
        .target(name: "CameraControlUseCase", dependencies: dependencies),
        .testTarget(name: "CameraControlUseCaseTests", dependencies: ["CameraControlUseCase"] + testDependencies),
        .target(name: "ExtensionInstallUseCase", dependencies: dependencies),
        .testTarget(name: "ExtensionInstallUseCaseTests", dependencies: ["ExtensionInstallUseCase"] + testDependencies),
        .target(name: "ExtensionRelayUseCase", dependencies: dependencies),
        .testTarget(name: "ExtensionRelayUseCaseTests", dependencies: ["ExtensionRelayUseCase"] + testDependencies),
        // Host only: the lite dev harness's solid frame (#21), until #24 runs the harness on the pipeline.
        .target(name: "SolidFrameUseCase", dependencies: dependencies),
        .testTarget(name: "SolidFrameUseCaseTests", dependencies: ["SolidFrameUseCase"] + testDependencies),

        // ── Interactor ──
        .target(name: "CameraInteractor", dependencies: dependencies),
        .testTarget(name: "CameraInteractorTests", dependencies: ["CameraInteractor"] + testDependencies),
        // Host only: the lite dev harness's launch sequence (#21).
        .target(name: "HarnessInteractor", dependencies: dependencies),
        .testTarget(name: "HarnessInteractorTests", dependencies: ["HarnessInteractor"] + testDependencies),

        // ── DependencyInjection (liveValue registrations only) ──
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
                "CameraInteractor", "HarnessInteractor",
                "FramePipelineUseCase", "CameraControlUseCase", "ExtensionInstallUseCase", "SolidFrameUseCase",
                "CameraRepository", "VirtualCameraRepository", "ExtensionInstallRepository",
                "EffectRuntimeRepository", "PreviewRepository",
                "CameraDataSource", "CameraPermissionDataSource", "FrameTransportDataSource", "ExtensionInstallDataSource",
                "BundledEffectDataSource", "ShaderCompilationDataSource", "GPURenderDataSource", "PreviewDataSource",
                "AVFoundationGateway", "MetalGateway", "MetalKitPreviewGateway", "SystemExtensionGateway",
            ]
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
        // is HarnessInteractor's, over SolidFrameUseCase and CameraControlUseCase.
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
        .testTarget(name: "DevHarnessTests", dependencies: ["DevHarness"] + testDependencies),

        // ── GPU smoke (own process via `make test-gpu`; never in the coverage run) ──
        // Imports Metal and IOSurface directly: a test target, not a Gateway, so the
        // import allow-list (Sources/ only) does not apply. .claude/rules/gpu-testing.md.
        .testTarget(
            name: "GPUSmokeTests",
            dependencies: dependencies + [
                "MetalGateway", "MetalKitPreviewGateway", "IOSurfaceGateway", "ShaderCompilationDataSource", "GPURenderDataSource",
                "PreviewDataSource", "Views", "TestDoubles", "TestSupport",
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
                "FrameReceiverDataSource", "StreamOutputDataSource",
            ]
        ),
    ]
)
