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
import TestSupport
import Testing

/// The host registers a live value for every port of the effect catalog (epic #42, D10):
/// the pass-through default of its module, until the later issue puts the real one there.
///
/// Every resolution here happens inside `withDependencies { $0.context = .live }`. The live
/// values in `HostRegistrations` are `static let`s: swift-dependencies builds each one on its
/// first resolution and keeps it for the life of the process (the test bundle is one
/// process), and a live value that resolves a port of its own (`EffectPackageRepositoryImpl`
/// resolves `effectPackages`, `effectWatch` and `bundledEffects`) captures the scope it is built in. These keys are resolved
/// by no other suite, and none of them is overridden here, so what each one captures is
/// the live context whichever test builds it first. Add no override in this suite and no
/// test that resolves one of these keys in another.
@Suite("Host registrations of the effect catalog", .timeLimit(.minutes(1)))
struct HostEffectRegistrationsTests {
    @Test("each port of the catalog has the live value of its module's pass-through")
    func everyPortHasItsPassThrough() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.effectInteractor) var effectInteractor
            @Dependency(\.effectCatalogUseCase) var effectCatalogUseCase
            @Dependency(\.effectPackageRepository) var effectPackageRepository
            @Dependency(\.settingsRepository) var settingsRepository
            @Dependency(\.effectPackages) var effectPackages
            @Dependency(\.effectWatch) var effectWatch
            @Dependency(\.preferences) var preferences

            #expect(effectInteractor is StaticEffectInteractor)
            #expect(effectCatalogUseCase is BundledOnlyEffectCatalog)
            #expect(effectPackageRepository is EffectPackageRepositoryImpl)
            #expect(settingsRepository is EmptySettings)
            #expect(effectPackages is NoPackages)
            #expect(effectWatch is NeverChangingWatch)
            #expect(preferences is EmptyPreferences)
        }
    }

    @Test("the default graph lists the bundled effect and nothing else, selected, through the live registrations")
    func defaultGraphIsBundledOnly() async {
        let state = await withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.effectCatalogUseCase) var useCase
            return useCase
        }.observe().first { _ in true }

        let entry = state?.entries.first
        #expect(state?.entries.count == 1)
        #expect(entry?.origin == .bundled)
        #expect(entry?.availability == .ready)
        #expect(state?.selection == entry?.id)
        #expect(state?.outcome == nil)
    }
}
