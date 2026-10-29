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
/// The Gateways the real implementations resolve and that would touch the machine are faked, in every
/// test: the file system and the app directories (`EffectPackageDataSourceImpl` lists and makes
/// the effects folder), `fileWatchGateway` (`EffectWatchDataSourceImpl` opens a descriptor on it), the
/// key-value store (the chosen effect) and Finder, and the logs they write to. That the fakes are
/// the ones the default graph reaches is asserted rather than assumed, for each of them but Finder:
/// the default-graph test reads back what the in-memory file system was asked (the folder made, then
/// listed), that the watch on the folder was armed on the fake file events with no "could not watch"
/// line in the developer log, and that nothing was logged as an error; the restore test seeds the
/// in-memory store with a choice only that store holds and reads the restored selection back. Finder
/// is overridden too, but nothing here calls `openFolder`: `HarnessLiveWiringTests` drives it to the
/// fake workspace.
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
    @Test("each stateless port of the catalog has the live value of its module's implementation")
    func everyStatelessPortHasItsImplementation() async {
        await Fakes().live {
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
        let fakes = Fakes()
        let (states, request) = try await runOnce(in: fakes)

        let state = try #require(states.first)
        let entry = try #require(state.entries.first)
        #expect(states.count == 1)
        #expect(state.entries.count == 1)
        #expect(entry.origin == .bundled)
        #expect(entry.availability == .ready)
        #expect(state.selection == entry.id)
        #expect(state.outcome == .prepared)
        #expect(request.effect.name == entry.displayName, "what the runtime was handed is the bundled effect the catalog lists")

        // The effects folder is the in-memory one: made once, then listed, and nothing went wrong on the way.
        #expect(fakes.files.createdDirectories.values == [Fakes.effectsDirectory], "the default graph makes the effects folder, in memory")
        #expect(fakes.files.isDirectory(Fakes.effectsDirectory))
        #expect(fakes.files.listings.values.contains(Fakes.effectsDirectory), "the default graph lists the effects folder, in memory")
        #expect(fakes.errors.entries.count == 0)

        // The watch on it is armed on the fake file events: the live gateway would throw for a folder that is not on this machine,
        // which the data source logs and skips, so only these two lines tell the fake from the live one.
        #expect(
            fakes.fileWatch.watches.values.contains(.init(kind: .directory, path: Fakes.effectsDirectory)),
            "the default graph arms a directory watch on the effects folder, on the fake file events")
        #expect(!fakes.developer.contains("could not watch"), "and no watch was skipped")
        #expect(fakes.store.writes.values.isEmpty, "choosing nothing writes nothing to the key-value store")
    }

    @Test("the default graph restores the choice the key-value store holds: a package that is in the in-memory folder")
    func defaultGraphRestoresTheStoredChoice() async throws {
        // `selectedEffect` and `package:<key>` are persisted names, pinned literally by the DataStore's own suite.
        let fakes = Fakes(storedValues: ["selectedEffect": "package:glitch"])
        fakes.files.write("\(Fakes.effectsDirectory)/glitch.lens/manifest.json", #"{"formatVersion": 1, "name": "Glitch"}"#)
        fakes.files.write("\(Fakes.effectsDirectory)/glitch.lens/effect.metal", Fakes.glitchShader)

        let (states, request) = try await runOnce(in: fakes)

        let state = try #require(states.first)
        let bundled = try #require(state.entries.first)
        #expect(states.count == 1)
        #expect(bundled.origin == .bundled)
        #expect(state.entries.map(\.id) == [bundled.id, .package("glitch")], "the bundled effect, then the package the folder holds")
        #expect(state.selection == .package("glitch"), "the choice the in-memory store held is the one restored")
        #expect(state.outcome == .prepared)
        #expect(request.effect.name == "Glitch", "what the runtime was handed is the restored package")
        #expect(request.effect.source == Fakes.glitchShader)
        #expect(fakes.store.writes.values.isEmpty, "restoring is not choosing: nothing is written back")
    }

    /// One run of the real UseCase over the live catalog, with the runtime held by a fake: the first `prepare` is answered, the first
    /// state is waited for, and the run is ended. The states it published and the request it was handed come back.
    private func runOnce(
        in fakes: Fakes
    ) async throws -> (states: [EffectCatalogState], request: FakeEffectRuntimeRepository.PrepareRequest) {
        let runtime = FakeEffectRuntimeRepository()
        let states = Collector<EffectCatalogState>()
        let request = try await fakes.live {
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
        return (states.values, request)
    }
}

/// The fakes one test hands the live graph in place of the machine's file system, app directories, file events,
/// key-value store and Finder, and the logs: kept, so a test can read back what the graph asked of them.
private struct Fakes {
    static let effectsDirectory = "/effects"
    static let glitchShader = "kernel void effect() {}\n"

    let files = InMemoryFileSystemGateway()
    let fileWatch = FakeFileWatchGateway()
    let store: InMemoryKeyValueStore
    let workspace = FakeWorkspaceGateway()
    let errors = RecordingLog()
    let developer = RecordingLog()

    /// `storedValues` is what the in-memory key-value store holds before the graph reads it.
    init(storedValues: [String: String] = [:]) {
        store = InMemoryKeyValueStore(storedValues)
    }

    func live<Value>(_ operation: () async throws -> Value) async rethrows -> Value {
        try await withDependencies {
            $0.context = .live
            $0.fileSystemGateway = files
            $0.appDirectories = FixedAppDirectories(effectsDirectory: Self.effectsDirectory)
            $0.fileWatchGateway = fileWatch
            $0.keyValueStoreGateway = store
            $0.workspaceGateway = workspace
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            try await operation()
        }
    }
}
