import Dependencies
import Domain
import SettingsUseCase
import TestDoubles
import Testing

@Suite("SettingsUseCaseImpl launch at login", .timeLimit(.minutes(1)))
struct SettingsUseCaseLoginTests {
    private func makeSubject(_ repository: FakeSettingsRepository, _ log: RecordingLog) -> SettingsUseCaseImpl {
        withDependencies {
            $0.settingsRepository = repository
            $0.developerLog = log
        } operation: {
            SettingsUseCaseImpl()
        }
    }

    @Test("launchAtLoginStatus is the repository's value")
    func statusIsRepositoryValue() {
        let repository = FakeSettingsRepository(launchAtLogin: .needsApproval)
        let subject = makeSubject(repository, RecordingLog())
        #expect(subject.launchAtLoginStatus == .needsApproval)
    }

    @Test("setLaunchAtLogin(true) reaches the repository once, and returns what the repository returns")
    func setReachesRepositoryOnce() {
        let repository = FakeSettingsRepository(launchAtLogin: .off)
        let subject = makeSubject(repository, RecordingLog())
        let status = subject.setLaunchAtLogin(true)
        #expect(repository.launchRequests.values == [true])
        #expect(status == repository.launchAtLoginStatus)
        #expect(status == .on)
    }

    @Test("openLoginItemsSettings() reaches the repository once")
    func openReachesRepositoryOnce() {
        let repository = FakeSettingsRepository()
        let subject = makeSubject(repository, RecordingLog())
        subject.openLoginItemsSettings()
        #expect(repository.settingsOpens.count == 1)
    }

    @Test("a request that takes effect logs launch at login now on")
    func logsRequestThatTookEffect() {
        let repository = FakeSettingsRepository(launchAtLogin: .off)
        let log = RecordingLog()
        _ = makeSubject(repository, log).setLaunchAtLogin(true)
        #expect(log.entries.values == [LogEntry(.app, "launch at login now on")])
    }

    @Test("turning the item off from on logs launch at login now off")
    func logsOffRequestThatTookEffect() {
        let repository = FakeSettingsRepository(launchAtLogin: .on)
        let log = RecordingLog()
        let status = makeSubject(repository, log).setLaunchAtLogin(false)
        #expect(status == .off)
        #expect(log.entries.values == [LogEntry(.app, "launch at login now off")])
    }

    // FakeSettingsRepository answers on or off for any status but unavailable, so "requested on, now off"
    // cannot be produced here. The mismatch branch and its log format are the same for any status.
    @Test("a request that does not change the status logs requested on, now unavailable")
    func logsRequestThatDidNotTakeEffect() {
        let repository = FakeSettingsRepository(launchAtLogin: .unavailable)
        let log = RecordingLog()
        let status = makeSubject(repository, log).setLaunchAtLogin(true)
        #expect(status == .unavailable)
        #expect(log.entries.values == [LogEntry(.app, "launch at login requested on, now unavailable")])
    }

    @Test("resetAll resets, stamps, then turns the login item off through the repository")
    func resetTurnsLoginItemOff() async {
        let repository = FakeSettingsRepository(schemaVersion: .version(7), launchAtLogin: .on)
        let log = RecordingLog()
        await makeSubject(repository, log).resetAll()
        #expect(repository.resets.count == 1)
        #expect(repository.stamps.values == [1])
        #expect(repository.launchRequests.values == [false])
        #expect(repository.launchAtLoginStatus == .off)
    }

    @Test("the fake answers a request with on or off, and leaves unavailable alone")
    func fakeAnswersRequests() {
        let fake = FakeSettingsUseCase(launchAtLogin: .off)
        #expect(fake.setLaunchAtLogin(true) == .on)
        #expect(fake.launchRequests.values == [true])
        let unavailable = FakeSettingsUseCase(launchAtLogin: .unavailable)
        #expect(unavailable.setLaunchAtLogin(true) == .unavailable)
        #expect(unavailable.launchAtLoginStatus == .unavailable)
    }
}
