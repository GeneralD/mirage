import Dependencies
import Domain
import EffectCatalogUseCase
import EffectPackageDataSource
import EffectPackageRepository
import EffectWatchDataSource
import HostDependencyInjection
import PreferencesDataStore
import SettingsRepository
import TestDoubles
import TestSupport
import Testing

/// The host registers the real implementation of its module for every stateless port of the effect
/// catalog (epic #42, D10): no pass-through of the catalog remains. The OS-boundary lives under them
/// (the file system, the file events, Finder, the app directories, the key-value store) are not
/// checked here: `HostFileGatewayRegistrationsTests` pins them.
/// The Gateways the real implementations resolve and that would touch the machine are faked, in both
/// tests: the file system and the app directories (`EffectPackageDataSourceImpl` lists and makes
/// the effects folder), `fileWatchGateway` (`EffectWatchDataSourceImpl` opens a descriptor on it), the
/// key-value store (the chosen effect) and Finder, and the logs they write to.
///
/// **Which keys this suite resolves, and which it leaves to `HarnessLiveWiringTests`.** The live values
/// in `HostRegistrations` are `static let`s: swift-dependencies builds each one on its first resolution
/// and keeps it for the life of the process (the test bundle is one process, and its suites run
/// concurrently). The catalog's values come in two kinds:
///
/// - **Stateless** (`effectPackageRepository`, `settingsRepository`, `effectPackages`, `effectWatch`,
///   `preferences`): structs that hold nothing between calls. A caller's own overrides win over the
///   scope such a value captured, so these are resolved here, inside `live(_:)`, with every Gateway
///   they reach overridden by a fake of this suite, whichever suite built the singleton first.
/// - **Stateful** (`effectInteractor`, `effectCatalogUseCase`): `EffectInteractorImpl` resolves the
///   catalog and the logs once and starts a supervising `Task`, which freezes the task-locals of the scope
///   that built it; `EffectCatalogUseCaseImpl` owns the catalog's session. The first scope that builds
///   them stays theirs for the process. **`HarnessLiveWiringTests` is the one suite that resolves them
///   live**, with the fakes of the whole harness graph, and checks their types there; this suite builds
///   its own `EffectCatalogUseCaseImpl` (not the registered singleton) and never resolves either key.
///
/// Everything here runs inside `live(_:)`, tasks included: a `Task` made inside it inherits its
/// overrides, so what the catalog's `run()` resolves is this test's file system and store even when a
/// singleton captured another suite's. Resolve nothing outside `live(_:)` in this suite, and add no
/// resolution of `effectInteractor` or `effectCatalogUseCase` (`docs/ARCHITECTURE.md` →
/// *The effect catalog follows the same rule*).
@Suite("Host registrations of the effect catalog", .timeLimit(.minutes(1)))
struct HostEffectRegistrationsTests {
    private static func live<Value>(_ operation: () async throws -> Value) async rethrows -> Value {
        try await withDependencies {
            $0.context = .live
            $0.fileSystemGateway = InMemoryFileSystemGateway()
            $0.appDirectories = FixedAppDirectories(effectsDirectory: "/effects")
            $0.fileWatchGateway = FakeFileWatchGateway()
            $0.keyValueStoreGateway = InMemoryKeyValueStore()
            $0.workspaceGateway = FakeWorkspaceGateway()
            $0.errorLog = RecordingLog()
            $0.developerLog = RecordingLog()
        } operation: {
            try await operation()
        }
    }

    @Test("each stateless port of the catalog has the live value of its module's implementation")
    func everyStatelessPortHasItsImplementation() async {
        await Self.live {
            @Dependency(\.effectPackageRepository) var effectPackageRepository
            @Dependency(\.settingsRepository) var settingsRepository
            @Dependency(\.effectPackages) var effectPackages
            @Dependency(\.effectWatch) var effectWatch
            @Dependency(\.preferences) var preferences

            #expect(effectPackageRepository is EffectPackageRepositoryImpl)
            #expect(settingsRepository is SettingsRepositoryImpl)
            #expect(effectPackages is EffectPackageDataSourceImpl)
            #expect(effectWatch is EffectWatchDataSourceImpl)
            #expect(preferences is PreferencesDataStoreImpl)
        }
    }

    @Test(
        "the default graph chooses the bundled effect and prepares it: the real UseCase over the live catalog and settings, the runtime held by a fake"
    )
    func defaultGraphChoosesTheBundledEffect() async throws {
        let runtime = FakeEffectRuntimeRepository()
        let states = Collector<EffectCatalogState>()
        let request = try await Self.live {
            let useCase = withDependencies {
                $0.effectRuntimeRepository = runtime
            } operation: {
                EffectCatalogUseCaseImpl()
            }
            let observer = Task { for await state in useCase.observe() { states.append(state) } }
            let run = Task { await useCase.run() }

            await runtime.prepareRequests.waitForCount(1)
            let request = try #require(runtime.prepareRequests.values.first)
            runtime.completePrepare(request, with: .success(()))
            await states.waitForCount(1)
            run.cancel()
            await run.value
            await observer.value
            return request
        }

        let state = try #require(states.values.first)
        let entry = try #require(state.entries.first)
        #expect(states.count == 1)
        #expect(state.entries.count == 1)
        #expect(entry.origin == .bundled)
        #expect(entry.availability == .ready)
        #expect(state.selection == entry.id)
        #expect(state.outcome == .prepared)
        #expect(request.effect.name == entry.displayName, "what the runtime was handed is the bundled effect the catalog lists")
    }
}
