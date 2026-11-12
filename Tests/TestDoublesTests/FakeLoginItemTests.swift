import Domain
import TestDoubles
import Testing

@Suite("FakeLoginItem")
struct FakeLoginItemTests {
    @Test("setEnabled(true) turns off into on")
    func enableTurnsOffIntoOn() {
        let item = FakeLoginItem(status: .off)
        #expect(item.setEnabled(true) == .on)
        #expect(item.status == .on)
    }

    @Test(
        "setEnabled(true) leaves on, needsApproval and unavailable as they are",
        arguments: [LaunchAtLoginStatus.on, .needsApproval, .unavailable])
    func enableLeavesOtherStatusesAlone(status: LaunchAtLoginStatus) {
        let item = FakeLoginItem(status: status)
        #expect(item.setEnabled(true) == status)
        #expect(item.status == status)
    }

    @Test(
        "setEnabled(false) turns on and needsApproval into off",
        arguments: [LaunchAtLoginStatus.on, .needsApproval])
    func disableTurnsOnAndNeedsApprovalIntoOff(status: LaunchAtLoginStatus) {
        let item = FakeLoginItem(status: status)
        #expect(item.setEnabled(false) == .off)
        #expect(item.status == .off)
    }

    @Test(
        "setEnabled(false) leaves off and unavailable as they are",
        arguments: [LaunchAtLoginStatus.off, .unavailable])
    func disableLeavesOffAndUnavailableAlone(status: LaunchAtLoginStatus) {
        let item = FakeLoginItem(status: status)
        #expect(item.setEnabled(false) == status)
        #expect(item.status == status)
    }

    @Test("requests records each value passed to setEnabled, in call order, including a no-op")
    func requestsInOrder() {
        let item = FakeLoginItem(status: .unavailable)
        _ = item.setEnabled(true)
        _ = item.setEnabled(false)
        #expect(item.requests.values == [true, false])
    }

    @Test("set(status:) changes the status the fake reports, whatever setEnabled did before")
    func setStatusIsReported() {
        let item = FakeLoginItem(status: .off)
        _ = item.setEnabled(true)
        item.set(status: .needsApproval)
        #expect(item.status == .needsApproval)
        item.set(status: .unavailable)
        #expect(item.status == .unavailable)
    }

    @Test("openSystemSettings is recorded once per call")
    func settingsOpensAreRecorded() {
        let item = FakeLoginItem()
        item.openSystemSettings()
        item.openSystemSettings()
        #expect(item.settingsOpens.count == 2)
        #expect(item.requests.count == 0)
    }
}
