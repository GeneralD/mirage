import Dependencies
import Domain
import LoginItemDataSource
import TestDoubles
import Testing

@Suite("LoginItemDataSourceImpl", .timeLimit(.minutes(1)))
struct LoginItemDataSourceTests {
    private func makeSubject(_ gateway: FakeLoginItemGateway, errors: RecordingLog) -> LoginItemDataSourceImpl {
        withDependencies {
            $0.loginItemGateway = gateway
            $0.errorLog = errors
        } operation: {
            LoginItemDataSourceImpl()
        }
    }

    @Test(
        "raw status 0, 1, 2, 3, 7 and -1 read as off, on, needsApproval, unavailable, unavailable and unavailable",
        arguments: [
            (0, LaunchAtLoginStatus.off),
            (1, .on),
            (2, .needsApproval),
            (3, .unavailable),
            (7, .unavailable),
            (-1, .unavailable),
        ])
    func rawStatusMapping(raw: Int, expected: LaunchAtLoginStatus) {
        let subject = makeSubject(FakeLoginItemGateway(status: raw), errors: RecordingLog())
        #expect(subject.status == expected)
    }

    @Test("status reads the gateway's current raw status each time, not a value kept from before")
    func statusFollowsGateway() {
        let gateway = FakeLoginItemGateway(status: 0)
        let subject = makeSubject(gateway, errors: RecordingLog())
        #expect(subject.status == .off)
        gateway.set(status: 2)
        #expect(subject.status == .needsApproval)
    }

    @Test("setEnabled(true) at off calls register once and returns on")
    func enableFromOffRegisters() {
        let gateway = FakeLoginItemGateway(status: 0)
        let errors = RecordingLog()
        let result = makeSubject(gateway, errors: errors).setEnabled(true)
        #expect(result == .on)
        #expect(gateway.registers.count == 1)
        #expect(gateway.unregisters.count == 0)
        #expect(errors.messages(in: .app).isEmpty)
    }

    @Test(
        "setEnabled(true) at on, needsApproval or unavailable calls no gateway and returns the original status",
        arguments: [
            (1, LaunchAtLoginStatus.on),
            (2, .needsApproval),
            (3, .unavailable),
        ])
    func enableLeavesOtherStatusesAlone(raw: Int, expected: LaunchAtLoginStatus) {
        let gateway = FakeLoginItemGateway(status: raw)
        let errors = RecordingLog()
        let result = makeSubject(gateway, errors: errors).setEnabled(true)
        #expect(result == expected)
        #expect(gateway.registers.count == 0)
        #expect(gateway.unregisters.count == 0)
        #expect(errors.messages(in: .app).isEmpty)
    }

    @Test(
        "setEnabled(false) at on and needsApproval calls unregister once and returns off",
        arguments: [1, 2])
    func disableFromOnOrNeedsApprovalUnregisters(raw: Int) {
        let gateway = FakeLoginItemGateway(status: raw)
        let errors = RecordingLog()
        let result = makeSubject(gateway, errors: errors).setEnabled(false)
        #expect(result == .off)
        #expect(gateway.unregisters.count == 1)
        #expect(gateway.registers.count == 0)
        #expect(errors.messages(in: .app).isEmpty)
    }

    @Test(
        "setEnabled(false) at off or unavailable calls no gateway and returns the original status",
        arguments: [
            (0, LaunchAtLoginStatus.off),
            (3, .unavailable),
        ])
    func disableLeavesOffAndUnavailableAlone(raw: Int, expected: LaunchAtLoginStatus) {
        let gateway = FakeLoginItemGateway(status: raw)
        let errors = RecordingLog()
        let result = makeSubject(gateway, errors: errors).setEnabled(false)
        #expect(result == expected)
        #expect(gateway.registers.count == 0)
        #expect(gateway.unregisters.count == 0)
        #expect(errors.messages(in: .app).isEmpty)
    }

    @Test("register that throws leaves the status at off, logs one launch at login line, and throws nothing out")
    func registerFailureStaysOffAndLogsOnce() {
        let gateway = FakeLoginItemGateway(status: 0)
        gateway.failNext(.alreadyRegistered)
        let errors = RecordingLog()
        let result = makeSubject(gateway, errors: errors).setEnabled(true)
        #expect(result == .off)
        #expect(gateway.registers.count == 1)
        let messages = errors.messages(in: .app)
        #expect(messages.count == 1)
        #expect(messages.first?.hasPrefix("launch at login:") == true)
    }

    @Test("unregister that throws leaves the status at on, logs one launch at login line, and throws nothing out")
    func unregisterFailureStaysOnAndLogsOnce() {
        let gateway = FakeLoginItemGateway(status: 1)
        gateway.failNext(.notRegistered)
        let errors = RecordingLog()
        let result = makeSubject(gateway, errors: errors).setEnabled(false)
        #expect(result == .on)
        #expect(gateway.unregisters.count == 1)
        let messages = errors.messages(in: .app)
        #expect(messages.count == 1)
        #expect(messages.first?.hasPrefix("launch at login:") == true)
    }

    @Test("openSystemSettings reaches the gateway once")
    func openSystemSettingsReachesGatewayOnce() {
        let gateway = FakeLoginItemGateway()
        makeSubject(gateway, errors: RecordingLog()).openSystemSettings()
        #expect(gateway.settingsOpens.count == 1)
        #expect(gateway.registers.count == 0)
        #expect(gateway.unregisters.count == 0)
    }
}
