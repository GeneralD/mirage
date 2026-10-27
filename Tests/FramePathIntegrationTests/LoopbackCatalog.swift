import BundledEffectDataSource
import Dependencies
import Domain
import EffectCatalogUseCase
import EffectPackageDataSource
import EffectPackageRepository
import EffectWatchDataSource
import PreferencesDataStore
import SettingsRepository
import TestDoubles
import TestSupport
import Testing

/// The effects menu's catalog as the host runs it (`HostCatalog.real`): `EffectCatalogUseCaseImpl`
/// over `EffectPackageRepositoryImpl`, `SettingsRepositoryImpl` and the runtime the pipeline applies,
/// those over `EffectPackageDataSourceImpl`, `EffectWatchDataSourceImpl` and `PreferencesDataStoreImpl`,
/// with only the OS boundary under them faked: the effects folder is an `InMemoryFileSystemGateway`
/// the test writes into, the file events are a `FakeFileWatchGateway` it fires, the chosen effect is kept
/// in an `InMemoryKeyValueStore`, and Finder is a `FakeWorkspaceGateway`.
///
/// **The watch has a clock of its own, a `GatedClock`.** An event travels from the watch's callback
/// through the debouncing task to a sleep on the clock, and a clock that cannot say when that sleep
/// is parked would let `advance` run before it, which loses the advance (`WatchRig` has the same
/// reason). The host's `TestClock` cannot say it, so the watch does not sleep on it: nothing else in
/// the catalog reads a clock, and the pipeline's reconnect keeps the host's.
struct CatalogSide {
    /// The effects folder, as `AppDirectoriesProvider` answers it.
    static let folder = "/effects"

    let fileSystem = InMemoryFileSystemGateway()
    let fileWatch = FakeFileWatchGateway()
    let store = InMemoryKeyValueStore()
    let workspace = FakeWorkspaceGateway()
    /// What the watch's quiet period sleeps on; `sleepers` fires once a sleep is parked.
    let clock = GatedClock()
    /// Every state the UseCase published since `startCatalog()`, in order.
    let states = Collector<EffectCatalogState>()
    let useCase: EffectCatalogUseCaseImpl

    init(over runtime: any EffectRuntimeRepository, errors: RecordingLog, developer: RecordingLog) {
        let fileSystem = fileSystem
        let fileWatch = fileWatch
        let store = store
        let workspace = workspace
        let clock = clock
        // Each layer is built inside the scope of the one below it, as `HostSide` builds its own.
        useCase = withDependencies {
            $0.fileSystemGateway = fileSystem
            $0.appDirectories = FixedAppDirectories(effectsDirectory: Self.folder)
            $0.workspaceGateway = workspace
            $0.fileWatchGateway = fileWatch
            $0.keyValueStoreGateway = store
            $0.bundledEffects = BundledEffectDataSourceImpl()
            $0.continuousClock = clock
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            withDependencies {
                $0.effectPackages = EffectPackageDataSourceImpl()
                $0.effectWatch = EffectWatchDataSourceImpl()
                $0.preferences = PreferencesDataStoreImpl()
            } operation: {
                withDependencies {
                    $0.effectPackageRepository = EffectPackageRepositoryImpl()
                    $0.settingsRepository = SettingsRepositoryImpl()
                    $0.effectRuntimeRepository = runtime
                } operation: {
                    EffectCatalogUseCaseImpl()
                }
            }
        }
    }
}

/// A catalog run in progress: the UseCase's `run()` and the observer that records its states.
struct CatalogRun {
    let run: Task<Void, Never>
    let observer: Task<Void, Never>
}

extension LoopbackRig {
    /// Pumps the host's executor until `condition` holds. The runtime's state hops onto it, so
    /// anything that waits for a `prepare` or an `apply` has to be pumped, not awaited.
    @MainActor
    @discardableResult
    func pumpHost(until condition: () -> Bool) async -> Bool {
        await tickUntil(tick: { host.executor.drain() }, until: condition)
    }

    /// Starts the catalog the way the effects menu's Interactor does (one `run()` and an observer
    /// of its states), and returns once the run has listed the folder, chosen the effect and had the
    /// runtime prepare it: the first state is published only then.
    @MainActor
    func startCatalog() async -> CatalogRun? {
        guard let catalog = host.catalog else {
            Issue.record("startCatalog needs a host built with catalog: .real")
            return nil
        }
        let useCase = catalog.useCase
        let states = catalog.states
        let observer = Task { for await state in useCase.observe() { states.append(state) } }
        let run = Task { await useCase.run() }
        guard await pumpHost(until: { states.count >= 1 }) else {
            Issue.record("the catalog never published its first state")
            run.cancel()
            observer.cancel()
            return nil
        }
        return CatalogRun(run: run, observer: observer)
    }

    /// Ends the run and waits for it, which ends the observer's stream too.
    func stopCatalog(_ running: CatalogRun) async {
        running.run.cancel()
        await running.run.value
        await running.observer.value
    }

    /// Chooses `id` through the UseCase, pumping the host's executor until it answers.
    @MainActor
    func choose(_ id: EffectID) async -> EffectSelectionOutcome? {
        guard let useCase = host.catalog?.useCase else {
            Issue.record("choose needs a host built with catalog: .real")
            return nil
        }
        let answers = Collector<EffectSelectionOutcome>()
        let choosing = Task { answers.append(await useCase.select(id)) }
        // Judged before waiting on the task: a `select` that never answers would otherwise hang here until the
        // suite's time limit and say nothing of why.
        guard await pumpHost(until: { answers.count == 1 }) else {
            Issue.record("select never answered")
            choosing.cancel()
            return nil
        }
        await choosing.value
        return answers.values.first
    }

    /// Fires the file watch on `path` and returns once the watch's quiet period is parked on the
    /// catalog's clock, so time can move it. Says so when nothing was watching `path`.
    @MainActor
    func fireWatch(_ path: String) async {
        guard let catalog = host.catalog else {
            Issue.record("fireWatch needs a host built with catalog: .real")
            return
        }
        let parked = catalog.clock.sleepers.count
        guard catalog.fileWatch.fire(path) > 0 else {
            Issue.record("nothing was watching \(path)")
            return
        }
        await catalog.clock.sleepers.waitForCount(parked + 1)
    }

    /// Lets the quiet period of a burst already fired (`fireWatch`) run out.
    func passQuietPeriod() {
        host.catalog?.clock.advance(by: EffectWatchDataSourceImpl.quietPeriod)
    }

    /// An edit as the folder sees it: the watch on `path` fires and the quiet period passes. The catalog
    /// lists the folder again on its own task; what a test waits for afterwards is the step's own outcome.
    @MainActor
    func editFolder(firing path: String) async {
        await fireWatch(path)
        passQuietPeriod()
    }
}
