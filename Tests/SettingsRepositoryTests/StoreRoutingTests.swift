import Dependencies
import Domain
import PreferencesDataStore
import TestDoubles
import TestSupport
import Testing

@testable import SettingsRepository

/// The Repository over the real flag DataStore and the fake store maintenance: the hotkeys flag goes to
/// `Preferences`, the schema version and the reset go to `StoreMaintenance`, and neither crosses over.
@Suite("SettingsRepositoryImpl store routing", .timeLimit(.minutes(1)))
struct StoreRoutingTests {
    private func makeSubject(
        store: InMemoryKeyValueStore,
        maintenance: FakeStoreMaintenance,
        log: RecordingLog = RecordingLog()
    ) -> SettingsRepositoryImpl {
        let preferences = withDependencies {
            $0.keyValueStoreGateway = store
            $0.developerLog = log
        } operation: {
            PreferencesDataStoreImpl()
        }
        return withDependencies {
            $0.preferences = preferences
            $0.storeMaintenance = maintenance
        } operation: {
            SettingsRepositoryImpl()
        }
    }

    @Test("setHotkeysEnabled(false) is read back as off, and is stored as \"0\" under hotkeysEnabled")
    func hotkeysOffIsStored() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store: store, maintenance: FakeStoreMaintenance())
        await subject.setHotkeysEnabled(false)
        #expect(await subject.hotkeysEnabled() == false)
        #expect(store.values == ["hotkeysEnabled": "0"])
    }

    @Test("with no flag stored, hotkeysEnabled is true, and reading it writes nothing")
    func nothingStoredIsOn() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store: store, maintenance: FakeStoreMaintenance())
        #expect(await subject.hotkeysEnabled() == true)
        #expect(store.writes.count == 0)
    }

    @Test("the hotkeys flag never reaches StoreMaintenance")
    func flagSkipsMaintenance() async {
        let maintenance = FakeStoreMaintenance()
        let subject = makeSubject(store: InMemoryKeyValueStore(), maintenance: maintenance)
        await subject.setHotkeysEnabled(true)
        #expect(maintenance.stamps.count == 0)
        #expect(maintenance.resets.count == 0)
    }

    @Test("stampSchemaVersion(1) reaches StoreMaintenance once, and storedSchemaVersion reads it back as .version(1)")
    func stampRoutesToMaintenance() async {
        let store = InMemoryKeyValueStore()
        let maintenance = FakeStoreMaintenance()
        let subject = makeSubject(store: store, maintenance: maintenance)
        await subject.stampSchemaVersion(1)
        #expect(maintenance.stamps.values == [1])
        #expect(await subject.storedSchemaVersion() == .version(1))
        #expect(store.writes.count == 0, "the schema version is not the flag's DataStore to keep")
    }

    @Test("storedSchemaVersion answers what StoreMaintenance holds, unreadable included, and reading it writes nothing")
    func schemaVersionReadsThrough() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store: store, maintenance: FakeStoreMaintenance(version: .unreadable))
        #expect(await subject.storedSchemaVersion() == .unreadable)
        #expect(store.writes.count == 0)
    }

    @Test("resetAll calls StoreMaintenance.resetAll once, and nothing is removed from the flag's store directly")
    func resetRoutesToMaintenance() async {
        let store = InMemoryKeyValueStore(["hotkeysEnabled": "0"])
        let maintenance = FakeStoreMaintenance(version: .version(1))
        let subject = makeSubject(store: store, maintenance: maintenance)
        await subject.resetAll()
        #expect(maintenance.resets.count == 1)
        #expect(maintenance.stamps.count == 0)
        #expect(store.resets.count == 0, "the reset is StoreMaintenance's to run")
    }
}
