import HotkeyGateway
import Testing

/// Smoke of the live gateway against Carbon, on the main actor where the OS requires it. The
/// status is not asserted: a session without a window server may refuse a hotkey, and the handle
/// is still given back by `release()` either way.
@MainActor
@Suite("HotkeyGatewayImpl", .timeLimit(.minutes(1)))
struct HotkeyGatewayTests {
    private let gateway = HotkeyGatewayImpl()

    @Test("observePresses returns a handle, and release() can give it back")
    func observePressesReturnsReleasableHandle() {
        let handle = gateway.observePresses { _ in }
        handle.release()
    }

    @Test("register of F19 with command, shift, option and control, a combination other apps rarely take, returns a handle release() can give back")
    func registerReturnsReleasableHandle() {
        let handle = gateway.register(id: 1, keyCode: 80, modifiers: 6912)
        handle.release()
    }

    @Test("registering the same id twice and releasing both handles does not crash")
    func registerSameIDTwiceReleasesBoth() {
        let first = gateway.register(id: 2, keyCode: 80, modifiers: 6912)
        let second = gateway.register(id: 2, keyCode: 80, modifiers: 6912)
        first.release()
        second.release()
    }
}
