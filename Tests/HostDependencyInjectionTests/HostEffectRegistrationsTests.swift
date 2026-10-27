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
/// resolves one of these keys in another. (The one override beyond `live(_:)` is the effect
/// runtime's, on a UseCase the test builds itself, inside the same scope: the catalog's
/// pass-throughs never resolve it, so what they capture is untouched.)
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

            #expect(effectInteractor is EffectInteractorImpl)  // the real one (#49), not a pass-through: it runs nothing until `start()`
            #expect(effectCatalogUseCase is EffectCatalogUseCaseImpl)
            #expect(effectPackageRepository is EffectPackageRepositoryImpl)
            #expect(settingsRepository is SettingsRepositoryImpl)
            #expect(effectPackages is EffectPackageDataSourceImpl)
            #expect(effectWatch is NeverChangingWatch)
            #expect(preferences is PreferencesDataStoreImpl)
            #expect(keyValueStoreGateway is KeyValueStoreGatewayImpl)
        }
    }

    @Test(
        "the default graph chooses the bundled effect and prepares it: the real UseCase over the live catalog and settings, the runtime held by a fake"
    )
    func defaultGraphChoosesTheBundledEffect() async throws {
        let runtime = FakeEffectRuntimeRepository()
        let useCase = Self.live {
            withDependencies {
                $0.effectRuntimeRepository = runtime
            } operation: {
                EffectCatalogUseCaseImpl()
            }
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
