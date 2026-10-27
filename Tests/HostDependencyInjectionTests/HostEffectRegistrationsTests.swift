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
import UserDefaultsGateway

/// The host registers a live value for every port of the effect catalog (epic #42, D10):
/// the pass-through default of its module, or the real implementation where one has landed.
/// The OS-boundary ports register no pass-through: their live is the Gateway itself, which
/// the registration only type-checks here and never calls (it would read the user's defaults).
/// The one Gateway that is faked is `fileWatchGateway`, in both tests: the real
/// `EffectWatchDataSourceImpl` resolves it, so a listing that asked for a watch (the effects
/// folder, once `EffectPackageDataSource` lists one) would otherwise open a real descriptor.
///
/// Every resolution here happens inside `withDependencies { $0.context = .live }`. The live
/// values in `HostRegistrations` are `static let`s: swift-dependencies builds each one on its
/// first resolution and keeps it for the life of the process (the test bundle is one
/// process), and a live value that resolves a port of its own (`EffectPackageRepositoryImpl`
/// resolves `effectPackages`, `effectWatch` and `bundledEffects`) captures the scope it is built in. These keys are resolved
/// by no other suite, and none of them is overridden here, so what each one captures is
/// the live context whichever test builds it first. Add no override of one of these keys
/// in this suite and no test that resolves one in another. (The watch gateway is the
/// exception: `EffectWatchDataSourceImpl` captures the gateway it is first built with, so
/// every test below that can build it installs a `FakeFileWatchGateway`, and what it
/// captures is a fake whichever test comes first. The other override is the effect
/// runtime's, on a UseCase the test builds itself: the catalog's pass-throughs never
/// resolve it, so what they capture is untouched.)
@Suite("Host registrations of the effect catalog", .timeLimit(.minutes(1)))
struct HostEffectRegistrationsTests {
    @Test("each port of the catalog has the live value of its module's pass-through")
    func everyPortHasItsPassThrough() {
        withDependencies {
            $0.context = .live
            $0.fileWatchGateway = FakeFileWatchGateway()
        } operation: {
            @Dependency(\.effectInteractor) var effectInteractor
            @Dependency(\.effectCatalogUseCase) var effectCatalogUseCase
            @Dependency(\.effectPackageRepository) var effectPackageRepository
            @Dependency(\.settingsRepository) var settingsRepository
            @Dependency(\.effectPackages) var effectPackages
            @Dependency(\.effectWatch) var effectWatch
            @Dependency(\.preferences) var preferences
            @Dependency(\.keyValueStoreGateway) var keyValueStoreGateway

            #expect(effectInteractor is EffectInteractorImpl)  // the real one (#49), not a pass-through: it runs nothing until `start()`
            #expect(effectCatalogUseCase is EffectCatalogUseCaseImpl)
            #expect(effectPackageRepository is EffectPackageRepositoryImpl)
            #expect(settingsRepository is SettingsRepositoryImpl)
            #expect(effectPackages is NoPackages)
            #expect(effectWatch is EffectWatchDataSourceImpl)
            #expect(preferences is PreferencesDataStoreImpl)
            #expect(keyValueStoreGateway is KeyValueStoreGatewayImpl)
        }
    }

    @Test(
        "the default graph chooses the bundled effect and prepares it: the real UseCase over the live catalog and settings, the runtime held by a fake"
    )
    func defaultGraphChoosesTheBundledEffect() async throws {
        let runtime = FakeEffectRuntimeRepository()
        let useCase = withDependencies {
            $0.context = .live
            $0.fileWatchGateway = FakeFileWatchGateway()
            $0.effectRuntimeRepository = runtime
        } operation: {
            EffectCatalogUseCaseImpl()
        }
        let states = Collector<EffectCatalogState>()
        let observer = Task { for await state in useCase.observe() { states.append(state) } }
        let run = Task { await useCase.run() }

        await runtime.prepareRequests.waitForCount(1)
        let request = try #require(runtime.prepareRequests.values.first)
        runtime.completePrepare(request, with: .success(()))
        await states.waitForCount(1)
        run.cancel()
        await run.value
        await observer.value

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
