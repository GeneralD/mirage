import Domain
import TestDoubles
import Testing

@Suite("FakeCaptureSessionGateway")
struct FakeCaptureSessionGatewayTests {
    @Test("setMirrored on a live handle records each call in the order it was made")
    func mirrorCallsInCallOrder() throws {
        let gateway = FakeCaptureSessionGateway()
        let handle = try gateway.start(descriptor: .hd720, capture: .standard, onFrame: { _ in }, onEnd: { _ in })
        handle.setMirrored(true)
        handle.setMirrored(false)
        handle.setMirrored(true)
        #expect(gateway.mirrorCalls == [true, false, true])
    }

    @Test("setMirrored on a stopped handle records nothing, even after an earlier live call")
    func stoppedHandleRecordsNothing() throws {
        let gateway = FakeCaptureSessionGateway()
        let handle = try gateway.start(descriptor: .hd720, capture: .standard, onFrame: { _ in }, onEnd: { _ in })
        handle.setMirrored(true)
        handle.stop()
        handle.setMirrored(false)
        #expect(gateway.mirrorCalls == [true])
    }
}
