import Clocks
import Dependencies
import Domain
import EffectCatalogUseCase
import EffectInteractor
import EffectPackageDataSource
import EffectPackageRepository
import EffectWatchDataSource
import HostDependencyInjection
import PreferencesDataStore
import SettingsRepository
import TestDoubles
import TestSupport
import Testing

@testable import DevHarness

/// The graph the harness launches, through the host's live registrations: `context = .live`, so
/// the interactor, the pipeline, the camera and surface Repositories and the sink are the
/// registrations of `HostRegistrations` (`HarnessInteractorImpl`, `FramePipelineUseCaseImpl`,
/// `CameraRepositoryImpl`, `VirtualCameraRepositoryImpl`, …), and so is the effects menu's: the
/// Presenter an `AppRouter` builds, over `EffectInteractorImpl`, `EffectCatalogUseCaseImpl`, the
/// Repositories, DataSources and DataStore under it, and the effect runtime the pipeline applies.
/// Only the OS boundary under them is a fake: the camera source and permission, IOSurface, the Mach
/// gateways, the executor, scheduler, work runner and clock, the logs, the GPU layer (`FakeGPUGateway`,
/// `FakeShaderLibraryGateway`, `FakeTextureCacheGateway`), and for the effects folder the file system,
/// the file events, the app directories, the key-value store and Finder. Nothing here constructs the
/// graph by hand — `HarnessWiringTests` does that, and `FramePathIntegrationTests` builds the catalog
/// by hand over the same fakes — so what this proves is the route the harness takes at launch:
/// `live()` wraps the construction, the substitution it applies reaches the pipeline that is resolved
/// later, lazily, from the registrations, and the menu's Presenter reaches a catalog that lists the
/// bundled effect, compiles it, keeps the choice and opens the folder.
///
/// There is deliberately ONE test here, and the rule is the bundle's, not this target's: no other test
/// may resolve the stateful values below live. The `liveValue`s in `HostRegistrations` are `static let`s:
/// swift-dependencies builds each on its first resolution and keeps it for the life of the process, and
/// `swift test` runs every test target in that one process, its suites concurrently. Those that hold state
/// or start a task freeze the scope they were built in: `EffectInteractorImpl` resolves the catalog and
/// the logs once and starts its supervising `Task`, `EffectCatalogUseCaseImpl` owns the catalog's session,
/// the runtime's state is confined to the executor, the GPU renderer keeps its context. A second suite
/// that resolved one of them live would not get its own fakes; it would be handed this test's singletons,
/// with their already-captured executor, logs and GPU layer.
///
/// **This suite is the only one that resolves `effectInteractor` and `effectCatalogUseCase` live**, so the
/// first scope that builds them is always this test's, and `scripts/check-live-owner.sh` (in `make check`)
/// fails when another test file names either key as a key path or calls `HarnessMenu.live()`, which
/// builds the live Router. The other suites that run `.live` are
/// `HostEffectRegistrationsTests` and `HostFileGatewayRegistrationsTests` (`HostDependencyInjectionTests`):
/// they resolve only values that hold nothing between calls (the Repositories, DataSources and DataStore
/// of the catalog, which are structs, and the OS-boundary Gateways) and never those two keys. A new `.live`
/// suite keeps to that.
///
/// **Every call that can reach a catalog value is made inside `wired { }`.** A stateless live value
/// keeps the scope of whoever built it first, and which suite that is depends on the order the
/// suites run in. A call made in a scope of its own, one the test opened with `withDependencies`, has
/// its overrides win over whatever the value captured; a call made outside one gets the captured
/// scope, which may be `HostEffectRegistrationsTests`'s file system, store and Finder. (A `Task` made
/// inside a scope inherits it, which is how the catalog's own run, started by the Interactor's `init`
/// inside the first `wired`, stays on this test's fakes.) The same holds the other way round, so
/// `HostEffectRegistrationsTests` resolves everything inside its own `live(_:)`.
///
/// Without the substitution the pipeline's sink is the real `VirtualCameraRepositoryImpl`,
/// whose `connect` looks the extension's Mach service up (nobody has checked in here) and
/// then waits out its back-off on the clock, so `start` never returns and `pipeline started`
/// never appears; that wait is what the bounded `tickUntil` below runs out of.
///
/// Nothing is written to the folder and no time is advanced here: what a package, an edit or a quiet
/// period does is `EffectCatalogIntegrationTests`'s (the same catalog over the same fakes).
@MainActor
@Suite("Dev harness live wiring", .timeLimit(.minutes(1)))
struct HarnessLiveWiringTests {
    @Test(
        "the graph the harness launches discards frames instead of connecting to an extension that is not there, and its menu lists, chooses and opens through the real catalog"
    )
    func liveGraphDiscardsFramesAndServesTheMenu() async {
        let kernel = InMemoryFrameTransport()
        let camera = FakeCameraSource()
        let executor = ManualFrameExecutor()
        let scheduler = ManualFrameScheduler()
        let developer = RecordingLog()
        let errors = RecordingLog()
        let ioSurface = FakeIOSurfaceGateway()
        let work = RecordingWorkRunner()
        let clock = TestClock<Duration>()
        let gpu = FakeGPUGateway()
        let shaders = FakeShaderLibraryGateway()
        let textures = FakeTextureCacheGateway()
        let fileSystem = InMemoryFileSystemGateway()
        let fileWatch = FakeFileWatchGateway()
        let store = InMemoryKeyValueStore()
        let workspace = FakeWorkspaceGateway()
        let folder = "/effects"
        // One set of fakes, applied to every scope this test opens (the suite's note says why each call is wrapped).
        let wiring: (inout DependencyValues) -> Void = {
            $0.context = .live
            $0.cameraSource = camera
            $0.cameraPermission = FakeCameraPermission(status: .authorized)
            $0.machBootstrapGateway = kernel.bootstrap(for: .host)
            $0.machMessageGateway = kernel.messaging(for: .host)
            $0.ioSurfaceGateway = ioSurface
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.workRunner = work
            $0.continuousClock = clock
            $0.errorLog = errors
            $0.developerLog = developer
            $0.gpuGateway = gpu
            $0.shaderLibraryGateway = shaders
            $0.textureCacheGateway = textures
            $0.fileSystemGateway = fileSystem
            $0.appDirectories = FixedAppDirectories(effectsDirectory: folder)
            $0.fileWatchGateway = fileWatch
            $0.keyValueStoreGateway = store
            $0.workspaceGateway = workspace
        }
        func wired<Value>(_ operation: () -> Value) -> Value {
            withDependencies(wiring, operation: operation)
        }
        let (session, menu) = wired {
            // Resolved here, in this scope, so that what the two singletons freeze is this test's.
            @Dependency(\.effectInteractor) var effectInteractor
            @Dependency(\.effectCatalogUseCase) var effectCatalogUseCase
            @Dependency(\.effectPackageRepository) var effectPackageRepository
            @Dependency(\.settingsRepository) var settingsRepository
            @Dependency(\.effectPackages) var effectPackages
            @Dependency(\.effectWatch) var effectWatch
            @Dependency(\.preferences) var preferences
            #expect(effectInteractor is EffectInteractorImpl)
            #expect(effectCatalogUseCase is EffectCatalogUseCaseImpl)
            #expect(effectPackageRepository is EffectPackageRepositoryImpl)
            #expect(settingsRepository is SettingsRepositoryImpl)
            #expect(effectPackages is EffectPackageDataSourceImpl)
            #expect(effectWatch is EffectWatchDataSourceImpl)
            #expect(preferences is PreferencesDataStoreImpl)
            // The menu, and the Router in it, beside the session and not inside the harness's substitution: the pair
            // `HarnessAppDelegate` builds, by the same two calls.
            return (HarnessSession.live(), HarnessMenu.live())
        }
        let presenter = menu.router.menuBarPresenter
        defer {
            menu.stop()
            session.stop()
        }

        wired {
            session.start()
            menu.start()
        }
        let started = await tickUntil(tick: { executor.drain() }, until: { developer.contains("pipeline started") })
        let listed = await tickUntil(tick: { executor.drain() }, until: { presenter.items.contains { $0.isSelected } })

        #expect(started, "the pipeline never started: its sink waits for an extension, so the substitution did not reach it")
        #expect(listed, "the menu never listed a chosen effect: the catalog did not run, or its first state never reached the Presenter")
        #expect(kernel.lookUps.count == 0, "nothing looked the extension's service up")
        #expect(camera.startCount == 1)
        #expect(camera.descriptor == .hd720)
        #expect(scheduler.isRunning)
        #expect(developer.messages(in: .camera) == ["camera authorization: authorized"])

        // The menu: the bundled effect alone, chosen and enabled, compiled once from its own source.
        let chromatic = EffectID.bundled("Chromatic Grain")
        let selectedEffectKey = "selectedEffect"  // the defaults key the choice lives under: persisted, so never renamed
        #expect(presenter.items.map(\.id) == [chromatic])
        #expect(presenter.items.map(\.title) == ["Chromatic Grain"])
        #expect(presenter.items.map(\.isSelected) == [true])
        #expect(presenter.items.map(\.isEnabled) == [true])
        #expect(presenter.status == nil)
        #expect(shaders.calls.count == 1, "the chosen effect is compiled once")
        // The effects folder: made, and watched for packages coming and going.
        #expect(fileSystem.isDirectory(folder), "the catalog makes the effects folder")
        #expect(fileWatch.activeWatches.map(\.path).contains(folder), "the catalog watches the effects folder")

        // The menu's two commands reach their Gateways: Finder, and the user's choice in the store.
        wired {
            presenter.openEffectsFolder()
            presenter.select(chromatic)
        }
        // The choice reaches the store first; the source read, the runtime's prepare and the Interactor's log line come
        // after it, so the select is over only when that line is there, and only then can the error log be judged.
        let selectDone = "select bundled/Chromatic Grain: prepared"
        let chosen = await tickUntil(
            tick: { executor.drain() },
            until: { workspace.opened.count == 1 && store.values[selectedEffectKey] != nil && developer.contains(selectDone) })

        #expect(chosen, "the command never reached Finder, the choice never reached the store, or the select did not end prepared")
        #expect(workspace.opened.values == [folder])
        #expect(store.values[selectedEffectKey] == "bundled:Chromatic Grain")
        #expect(errors.entries.count == 0)
    }
}
