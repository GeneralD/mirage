import LoginItemGateway
import Testing

/// The live smoke of the login item gateway. It only reads the status: `register`, `unregister` and
/// `openSystemSettings` would change the login items and System Settings of the machine running the
/// tests, so they are not called here. What they do is left to the app's own check.
@Suite("LoginItemGatewayImpl", .timeLimit(.minutes(1)))
struct LoginItemGatewayTests {
    @Test("rawStatus is one of the four SMAppService.Status raw values")
    func rawStatusIsAKnownValue() {
        #expect((0...3).contains(LoginItemGatewayImpl().rawStatus()))
    }
}
