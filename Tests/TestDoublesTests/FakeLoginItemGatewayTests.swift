import Domain
import TestDoubles
import Testing

@Suite("FakeLoginItemGateway")
struct FakeLoginItemGatewayTests {
    @Test("a fake made without a status reads as notRegistered")
    func defaultStatusIsNotRegistered() {
        #expect(FakeLoginItemGateway().rawStatus() == 0)
    }

    @Test("register sets the status to enabled, and a second register throws alreadyRegistered")
    func registerTwice() throws {
        let gateway = FakeLoginItemGateway()
        try gateway.register()
        #expect(gateway.rawStatus() == 1)
        #expect(throws: FakeLoginItemGateway.Failure.alreadyRegistered) { try gateway.register() }
        #expect(gateway.rawStatus() == 1)
    }

    @Test("unregister sets the status to notRegistered, and a second unregister throws notRegistered")
    func unregisterTwice() throws {
        let gateway = FakeLoginItemGateway(status: 1)
        try gateway.unregister()
        #expect(gateway.rawStatus() == 0)
        #expect(throws: FakeLoginItemGateway.Failure.notRegistered) { try gateway.unregister() }
        #expect(gateway.rawStatus() == 0)
    }

    @Test("unregister throws notRegistered from notFound, and leaves the status at notFound")
    func unregisterFromNotFound() {
        let gateway = FakeLoginItemGateway(status: 3)
        #expect(throws: FakeLoginItemGateway.Failure.notRegistered) { try gateway.unregister() }
        #expect(gateway.rawStatus() == 3)
    }

    @Test("register from requiresApproval succeeds and sets the status to enabled")
    func registerFromRequiresApproval() throws {
        let gateway = FakeLoginItemGateway(status: 2)
        try gateway.register()
        #expect(gateway.rawStatus() == 1)
    }

    @Test("unregister from requiresApproval succeeds and sets the status to notRegistered")
    func unregisterFromRequiresApproval() throws {
        let gateway = FakeLoginItemGateway(status: 2)
        try gateway.unregister()
        #expect(gateway.rawStatus() == 0)
    }

    @Test("failNext makes only the next call fail, and the status does not change")
    func failNextFailsOnce() throws {
        let gateway = FakeLoginItemGateway()
        gateway.failNext(.alreadyRegistered)
        #expect(throws: FakeLoginItemGateway.Failure.alreadyRegistered) { try gateway.register() }
        #expect(gateway.rawStatus() == 0)
        try gateway.register()
        #expect(gateway.rawStatus() == 1)
    }

    @Test("failNext applies to unregister too, and is consumed by whichever call comes first")
    func failNextAppliesToUnregister() throws {
        let gateway = FakeLoginItemGateway(status: 1)
        gateway.failNext(.notRegistered)
        #expect(throws: FakeLoginItemGateway.Failure.notRegistered) { try gateway.unregister() }
        #expect(gateway.rawStatus() == 1)
        try gateway.unregister()
        #expect(gateway.rawStatus() == 0)
    }

    @Test("a failed register is still recorded, and so is a failed unregister")
    func failedCallsAreRecorded() throws {
        let gateway = FakeLoginItemGateway()
        #expect(throws: FakeLoginItemGateway.Failure.notRegistered) { try gateway.unregister() }
        try gateway.register()
        #expect(throws: FakeLoginItemGateway.Failure.alreadyRegistered) { try gateway.register() }
        #expect(gateway.registers.count == 2)
        #expect(gateway.unregisters.count == 1)
    }

    @Test("set(status:) changes what rawStatus reports, whatever the calls did before")
    func setStatusIsReported() throws {
        let gateway = FakeLoginItemGateway()
        try gateway.register()
        gateway.set(status: 2)
        #expect(gateway.rawStatus() == 2)
        gateway.set(status: 3)
        #expect(gateway.rawStatus() == 3)
    }

    @Test("openSystemSettings is recorded once per call")
    func settingsOpensAreRecorded() {
        let gateway = FakeLoginItemGateway()
        gateway.openSystemSettings()
        gateway.openSystemSettings()
        #expect(gateway.settingsOpens.count == 2)
        #expect(gateway.registers.count == 0)
        #expect(gateway.unregisters.count == 0)
    }
}
