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
        // Host only. Pass-through live values until #19 / #20 add the real runtime
        // and preview sink to the same modules (epic #14, D18).
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

        // ── Interactor ──
        .target(name: "CameraInteractor", dependencies: dependencies),
        .testTarget(name: "CameraInteractorTests", dependencies: ["CameraInteractor"] + testDependencies),

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
                "CameraInteractor",
                "FramePipelineUseCase", "CameraControlUseCase", "ExtensionInstallUseCase",
                "CameraRepository", "VirtualCameraRepository", "ExtensionInstallRepository",
                "EffectRuntimeRepository", "PreviewRepository",
                "CameraDataSource", "CameraPermissionDataSource", "FrameTransportDataSource", "ExtensionInstallDataSource",
                "AVFoundationGateway", "MetalGateway", "SystemExtensionGateway",
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

        // ── Entry ──
        .target(name: "App", dependencies: dependencies + ["HostDependencyInjection"]),
        .target(name: "ExtensionApp", dependencies: dependencies + ["ExtensionDependencyInjection"]),

        // ── GPU smoke (own process via `make test-gpu`; never in the coverage run) ──
        // Imports Metal and IOSurface directly: a test target, not a Gateway, so the
        // import allow-list (Sources/ only) does not apply. .claude/rules/gpu-testing.md.
        .testTarget(
            name: "GPUSmokeTests",
            dependencies: dependencies + ["MetalGateway", "IOSurfaceGateway", "ShaderCompilationDataSource", "TestDoubles", "TestSupport"]
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
