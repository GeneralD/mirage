import Dependencies
import Domain
import TestDoubles
import Testing

@testable import StoreMaintenanceDataStore

@Suite("StoreMaintenanceDataStoreImpl", .timeLimit(.minutes(1)))
struct StoreMaintenanceDataStoreTests {
    private func makeSubject(_ store: InMemoryKeyValueStore, log: RecordingLog = RecordingLog()) -> StoreMaintenanceDataStoreImpl {
        withDependencies {
            $0.keyValueStoreGateway = store
            $0.developerLog = log
        } operation: {
            StoreMaintenanceDataStoreImpl()
        }
    }

    @Test("nothing was ever stamped is missing, with nothing written and nothing logged")
    func nothingStamped() async {
        let store = InMemoryKeyValueStore()
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).schemaVersion() == .missing)
        #expect(store.writes.count == 0)
        #expect(log.entries.count == 0)
    }

    @Test("stampSchemaVersion(1) stores \"1\" under storeSchemaVersion, and schemaVersion() reads .version(1)")
    func stampedForm() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        await subject.stampSchemaVersion(1)
        #expect(store.values == ["storeSchemaVersion": "1"])
        #expect(store.writes.values == ["storeSchemaVersion"])
        #expect(await subject.schemaVersion() == .version(1))
    }

    @Test("the stamped version is read again by the next subject over the same store, as after a relaunch")
    func surviveRelaunch() async {
        let store = InMemoryKeyValueStore()
        await makeSubject(store).stampSchemaVersion(2)
        #expect(await makeSubject(store).schemaVersion() == .version(2))
    }

    @Test(
        "a stored value that does not read as a version is unreadable, logged once in the app subsystem, and left where it is",
        arguments: ["abc", "0", "-2", ""])
    func unreadable(stored: String) async {
        let store = InMemoryKeyValueStore(["storeSchemaVersion": stored])
        let log = RecordingLog()
        let subject = makeSubject(store, log: log)

        #expect(await subject.schemaVersion() == .unreadable)
        #expect(log.entries.count == 1)
        #expect(log.messages(in: .app).count == 1, "it is an app line")
        #expect(log.contains("does not decode"))
        #expect(store.values == ["storeSchemaVersion": stored], "another build may write it, and read it again")
        #expect(store.writes.count == 0)
    }

    @Test("a stamp replaces an unreadable value under the same key")
    func stampReplacesUnreadable() async {
        let store = InMemoryKeyValueStore(["storeSchemaVersion": "abc"])
        let subject = makeSubject(store)
        await subject.stampSchemaVersion(1)
        #expect(await subject.schemaVersion() == .version(1))
        #expect(store.values == ["storeSchemaVersion": "1"])
    }

    @Test("stamping the version leaves the chosen effect and every other key as they were")
    func otherKeysUntouched() async {
        let store = InMemoryKeyValueStore(["selectedEffect": "package:glitch"])
        await makeSubject(store).stampSchemaVersion(1)
        #expect(store.values == ["selectedEffect": "package:glitch", "storeSchemaVersion": "1"])
    }

    @Test("resetAll removes every stored value, the selection included, and the version reads missing again")
    func resetAllRemovesEverything() async {
        let store = InMemoryKeyValueStore(["selectedEffect": "package:glitch", "storeSchemaVersion": "2"])
        let log = RecordingLog()
        let subject = makeSubject(store, log: log)

        await subject.resetAll()

        #expect(store.values.isEmpty)
        #expect(await subject.schemaVersion() == .missing)
        #expect(store.resets.count == 1)
        #expect(store.writes.count == 0, "the reset is a removeAll, not a write per key")
        #expect(log.messages(in: .app) == ["store reset"])
    }
}
