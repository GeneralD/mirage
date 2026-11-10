import Dependencies
import Domain
import SettingsUseCase
import TestDoubles
import Testing

@Suite("SettingsUseCaseImpl", .timeLimit(.minutes(1)))
struct SettingsUseCaseTests {
    private func makeSubject(_ repository: FakeSettingsRepository, _ log: RecordingLog) -> SettingsUseCaseImpl {
        withDependencies {
            $0.settingsRepository = repository
            $0.developerLog = log
        } operation: {
            SettingsUseCaseImpl()
        }
    }

    @Test("prepareStore stamps version 1 when nothing is stored, and logs the stamp")
    func stampsWhenNothingIsStored() async {
        let repository = FakeSettingsRepository(schemaVersion: .missing)
        let log = RecordingLog()
        await makeSubject(repository, log).prepareStore()
        let stored = await repository.storedSchemaVersion()
        #expect(repository.stamps.values == [1])
        #expect(stored == .version(1))
        #expect(log.entries.values == [LogEntry(.app, "store schema stamped: v1")])
    }

    @Test("prepareStore writes nothing and logs nothing when version 1 is already stored")
    func leavesCurrentVersionAlone() async {
        let repository = FakeSettingsRepository(schemaVersion: .version(1))
        let log = RecordingLog()
        await makeSubject(repository, log).prepareStore()
        let stored = await repository.storedSchemaVersion()
        #expect(stored == .version(1))
        #expect(repository.stamps.values.isEmpty)
        #expect(repository.resets.count == 0)
        #expect(log.entries.values.isEmpty)
    }

    @Test("prepareStore writes nothing and logs one line when a newer version 7 is stored")
    func leavesNewerVersionAlone() async {
        let repository = FakeSettingsRepository(schemaVersion: .version(7))
        let log = RecordingLog()
        await makeSubject(repository, log).prepareStore()
        let stored = await repository.storedSchemaVersion()
        #expect(stored == .version(7))
        #expect(repository.stamps.values.isEmpty)
        #expect(repository.resets.count == 0)
        #expect(log.entries.values == [LogEntry(.app, "store schema v7 is newer than this build (v1), left as it is")])
    }

    @Test("prepareStore writes nothing and logs one line when the stored version is unreadable")
    func leavesUnreadableAlone() async {
        let repository = FakeSettingsRepository(schemaVersion: .unreadable)
        let log = RecordingLog()
        await makeSubject(repository, log).prepareStore()
        let stored = await repository.storedSchemaVersion()
        #expect(stored == .unreadable)
        #expect(repository.stamps.values.isEmpty)
        #expect(repository.resets.count == 0)
        #expect(log.entries.values == [LogEntry(.app, "store schema is unreadable, left as it is")])
    }

    @Test("resetAll resets the repository once, then stamps version 1, and logs the reset")
    func resetsThenStamps() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: false, schemaVersion: .version(7))
        let log = RecordingLog()
        await makeSubject(repository, log).resetAll()
        let stored = await repository.storedSchemaVersion()
        let hotkeys = await repository.hotkeysEnabled()
        #expect(repository.resets.count == 1)
        #expect(repository.stamps.values == [1])
        // A stamp that ran before the reset would have been cleared by it, so the stored version proves the order.
        #expect(stored == .version(1))
        #expect(hotkeys == true)
        #expect(log.entries.values == [LogEntry(.app, "settings reset")])
    }
}
