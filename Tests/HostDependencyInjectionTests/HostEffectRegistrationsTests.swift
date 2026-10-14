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
/// the pass-through default of its module, until the later issue puts the real one there.
/// The OS-boundary ports register no pass-through: their live is the Gateway itself, which
/// the registration only type-checks here and never calls (it would read the user's defaults).
///
/// Every resolution here happens inside `live(_:)`: `withDependencies { $0.context = .live }` over
/// an in-memory file system and a fixed effects folder. The live values in `HostRegistrations`
/// are `static let`s: swift-dependencies builds each one on its first resolution and keeps it for
/// the life of the process (the test bundle is one process), and a live value that resolves a port
/// of its own (`EffectPackageRepositoryImpl` resolves `effectPackages`, `effectWatch` and
/// `bundledEffects`; `EffectPackageDataSourceImpl` resolves the file system) captures the scope it is
/// built in. These keys are resolved by no other suite and every test of this one resolves them
/// through `live(_:)`, so what each one captures is the same scope whichever test builds it first.
/// The file system is the one thing that is not live: the first catalog the default graph asks for
/// lists the effects folder (and makes it), and a test must neither make the user's own folder nor
/// see what is in it. Resolve nothing through any other scope in this suite, and no test that
/// resolves one of these keys in another.
@Suite("Host registrations of the effect catalog", .timeLimit(.minutes(1)))
struct HostEffectRegistrationsTests {
    private static func live<Value>(_ operation: () -> Value) -> Value {
        withDependencies {
            $0.context = .live
            $0.fileSystemGateway = InMemoryFileSystemGateway()
            $0.appDirectories = FixedAppDirectories(effectsDirectory: "/effects")
        } operation: {
            operation()
        }
    }

    @Test("each port of the catalog has the live value of its module's pass-through")
    func everyPortHasItsPassThrough() {
        Self.live {
            @Dependency(\.effectInteractor) var effectInteractor
            @Dependency(\.effectCatalogUseCase) var effectCatalogUseCase
            @Dependency(\.effectPackageRepository) var effectPackageRepository
            @Dependency(\.settingsRepository) var settingsRepository
            @Dependency(\.effectPackages) var effectPackages
            @Dependency(\.effectWatch) var effectWatch
            @Dependency(\.preferences) var preferences
            @Dependency(\.keyValueStoreGateway) var keyValueStoreGateway

            #expect(effectInteractor is StaticEffectInteractor)
            #expect(effectCatalogUseCase is BundledOnlyEffectCatalog)
            #expect(effectPackageRepository is EffectPackageRepositoryImpl)
            #expect(settingsRepository is SettingsRepositoryImpl)
            #expect(effectPackages is EffectPackageDataSourceImpl)
            #expect(effectWatch is NeverChangingWatch)
            #expect(preferences is PreferencesDataStoreImpl)
            #expect(keyValueStoreGateway is KeyValueStoreGatewayImpl)
        }
    }

    @Test("the default graph lists the bundled effect and nothing else, selected, through the live registrations")
    func defaultGraphIsBundledOnly() async {
        let state = await Self.live {
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
