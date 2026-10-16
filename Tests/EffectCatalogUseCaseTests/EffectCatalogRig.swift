import Dependencies
import Domain
import EffectCatalogUseCase
import TestDoubles
import TestSupport
import Testing

/// The subject over the three fakes it is made of, with the effects every suite here writes
/// over: a bundled one and two packages. The runtime fake never answers on its own — a test
/// answers each `prepare` by hand, in the order it chooses (`answer`).
struct EffectCatalogRig {
    static let bundled = EffectCatalogEntry.fixture(.bundled("chromatic"), displayName: "Chromatic Grain")
    static let glitch = EffectCatalogEntry.fixture(.package("glitch"), displayName: "Glitch")
    static let other = EffectCatalogEntry.fixture(.package("other"), displayName: "Other")

    static let bundledSource = EffectSource(name: "Chromatic Grain", source: "bundled v1")
    static let glitchSource = EffectSource(name: "Glitch", source: "glitch v1")
    static let otherSource = EffectSource(name: "Other", source: "other v1")

    /// The source `source(of:)` answers for each effect above until a test scripts another.
    static let sources: [EffectID: EffectSource] = [
        bundled.id: bundledSource, glitch.id: glitchSource, other.id: otherSource,
    ]

    let packages: FakeEffectPackageRepository
    let runtime: FakeEffectRuntimeRepository
    let settings: FakeSettingsRepository
    let log: RecordingLog
    let subject: EffectCatalogUseCaseImpl

    /// - Parameters:
    ///   - entries: the catalog the Repository starts with; `nil` lists nothing until the test publishes.
    ///   - persisted: the effect the settings remember from the last launch.
    init(
        entries: [EffectCatalogEntry]? = [Self.bundled, Self.glitch, Self.other], persisted: EffectID? = nil,
        sources: [EffectID: EffectSource] = Self.sources
    ) {
        let packages = FakeEffectPackageRepository(entries: entries)
        for (id, source) in sources { packages.script(.success(source), for: id) }
        let runtime = FakeEffectRuntimeRepository()
        let settings = FakeSettingsRepository(selected: persisted)
        let log = RecordingLog()
        self.packages = packages
        self.runtime = runtime
        self.settings = settings
        self.log = log
        subject = withDependencies {
            $0.effectPackageRepository = packages
            $0.effectRuntimeRepository = runtime
            $0.settingsRepository = settings
            $0.developerLog = log
            $0.errorLog = log
        } operation: {
            EffectCatalogUseCaseImpl()
        }
    }

    /// What one `observe()` stream delivered, whether it has ended, and the task that reads it.
    struct Watcher {
        let states: Collector<EffectCatalogState>
        let ended: Collector<Void>
        let consumer: Task<Void, Never>
    }

    /// Starts the one task that keeps the catalog alive. Cancel it only when no `prepare` is pending:
    /// the runtime fake ignores cancellation, as the live runtime does.
    func start() -> Task<Void, Never> {
        let subject = subject
        return Task { await subject.run() }
    }

    func stop(_ run: Task<Void, Never>) async {
        run.cancel()
        await run.value
    }

    /// Opens an observer. The stream is subscribed before this returns, so a state published
    /// after is never missed.
    func watch() -> Watcher {
        let states = Collector<EffectCatalogState>()
        let ended = Collector<Void>()
        let stream = subject.observe()
        let consumer = Task {
            for await state in stream { states.append(state) }
            ended.append(())
        }
        return Watcher(states: states, ended: ended, consumer: consumer)
    }

    /// Waits for the runtime's `n`-th `prepare` (1-based, in call order) and answers it.
    @discardableResult
    func answer(_ n: Int, with result: Result<Void, EffectFailure> = .success(())) async -> FakeEffectRuntimeRepository.PrepareRequest {
        await runtime.prepareRequests.waitForCount(n)
        let request = runtime.prepareRequests.values[n - 1]
        #expect(runtime.completePrepare(request, with: result), "prepare #\(n) was already answered")
        return request
    }

    /// The state of a menu that lists `entries` and has chosen `selection`.
    static func state(
        _ entries: [EffectCatalogEntry] = [bundled, glitch, other], selection: EffectCatalogEntry = bundled,
        outcome: EffectSelectionOutcome? = .prepared
    ) -> EffectCatalogState {
        EffectCatalogState(entries: entries, selection: selection.id, outcome: outcome)
    }
}
