import Domain
import TestSupport
import Testing

@MainActor
@Suite("FrameReceiverDataSource registration", .timeLimit(.minutes(1)))
struct RegistrationTests {
    @Test("checkIn succeeds: listening is announced and register is never tried")
    func checkInSucceeds() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        #expect(rig.events.values == [.listening])
        try await rig.finish(task)

        #expect(rig.bootstrap.checkIns.values == [ProductIdentity.machServiceName])
        #expect(rig.bootstrap.registrations.values.isEmpty)
        #expect(rig.machMessage.receiveCalls.values.first == ReceiverRig.firstPort)
    }

    @Test("checkIn fails: register is the fallback and the checkIn code is traced")
    func fallsBackToRegister() async throws {
        let rig = ReceiverRig()
        rig.bootstrap.scriptCheckIn([.failure(.checkInFailed(code: 1100))])
        let task = await rig.listen()

        #expect(rig.events.values == [.listening])
        try await rig.finish(task)

        #expect(rig.bootstrap.registrations.values == [ProductIdentity.machServiceName])
        #expect(rig.developer.contains("1100"))
        #expect(rig.errors.entries.count == 0)
    }

    @Test("both routes fail: start throws the register error and both codes are logged")
    func bothRoutesFail() async throws {
        let rig = ReceiverRig()
        rig.bootstrap.scriptCheckIn([.failure(.checkInFailed(code: 1100))])
        rig.bootstrap.scriptRegister([.failure(.registerFailed(code: 1101))])
        let task = rig.start()

        let error = await #expect(throws: MachError.self) { try await task.value }

        #expect(error == .registerFailed(code: 1101))
        #expect(rig.errors.contains("1100"))
        #expect(rig.errors.contains("1101"))
        #expect(rig.events.values.isEmpty)
        #expect(rig.machMessage.receiveCalls.values.isEmpty)
    }
}
