import Domain
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("FakeHotkeyGateway", .timeLimit(.minutes(1)))
struct FakeHotkeyGatewayTests {
    private let gateway = FakeHotkeyGateway()

    @Test("register records the id, the key code and the modifiers of every call, in order")
    func registerIsRecorded() {
        _ = gateway.register(id: 1, keyCode: 80, modifiers: 6912)
        _ = gateway.register(id: 2, keyCode: 81, modifiers: 6912)
        #expect(
            gateway.registrations.values == [
                .init(id: 1, keyCode: 80, modifiers: 6912),
                .init(id: 2, keyCode: 81, modifiers: 6912),
            ])
    }

    @Test("register hands back the status script set for its id, and 0 when nothing was scripted")
    func scriptedStatusIsHandedBack() {
        gateway.script(status: -9878, forID: 2)
        #expect(gateway.register(id: 1, keyCode: 80, modifiers: 6912).status == 0)
        #expect(gateway.register(id: 2, keyCode: 80, modifiers: 6912).status == -9878)
    }

    @Test("observePresses records every call in observations")
    func observePressesIsRecorded() {
        _ = gateway.observePresses { _ in }
        _ = gateway.observePresses { _ in }
        #expect(gateway.observations.count == 2)
    }

    @Test("failObserve makes the observer handles that follow carry its status, and 0 is the default")
    func failObserveSetsTheStatus() {
        #expect(gateway.observePresses { _ in }.status == 0)
        gateway.failObserve(with: -1)
        #expect(gateway.observePresses { _ in }.status == -1)
    }

    @Test("press reaches the observer for a registered id, and says that it did")
    func pressReachesTheObserver() {
        let heard = Collector<UInt32>()
        _ = gateway.observePresses { heard.append($0) }
        _ = gateway.register(id: 7, keyCode: 80, modifiers: 6912)
        #expect(gateway.press(id: 7))
        #expect(heard.values == [7])
    }

    @Test("press does not reach the observer for an id that was never registered")
    func pressIgnoresAnUnregisteredID() {
        let heard = Collector<UInt32>()
        _ = gateway.observePresses { heard.append($0) }
        _ = gateway.register(id: 7, keyCode: 80, modifiers: 6912)
        #expect(!gateway.press(id: 8))
        #expect(heard.count == 0)
    }

    @Test("press does not reach the observer for a released hotkey")
    func pressIgnoresAReleasedHotkey() {
        let heard = Collector<UInt32>()
        _ = gateway.observePresses { heard.append($0) }
        let hotkey = gateway.register(id: 7, keyCode: 80, modifiers: 6912)
        hotkey.release()
        #expect(!gateway.press(id: 7))
        #expect(heard.count == 0)
    }

    @Test("press does not reach the observer for a hotkey whose status is not 0")
    func pressIgnoresAHotkeyThatFailed() {
        let heard = Collector<UInt32>()
        gateway.script(status: -9878, forID: 7)
        _ = gateway.observePresses { heard.append($0) }
        _ = gateway.register(id: 7, keyCode: 80, modifiers: 6912)
        #expect(!gateway.press(id: 7))
        #expect(heard.count == 0)
    }

    @Test("press does not reach the observer after the observer was released")
    func pressIgnoresAReleasedObserver() {
        let heard = Collector<UInt32>()
        let observer = gateway.observePresses { heard.append($0) }
        _ = gateway.register(id: 7, keyCode: 80, modifiers: 6912)
        observer.release()
        #expect(!gateway.press(id: 7))
        #expect(heard.count == 0)
    }

    @Test("liveHandleCount counts the observer and hotkey handles not yet released")
    func liveHandleCountCountsTheUnreleased() {
        let observer = gateway.observePresses { _ in }
        let hotkey = gateway.register(id: 1, keyCode: 80, modifiers: 6912)
        #expect(gateway.liveHandleCount == 2)
        hotkey.release()
        #expect(gateway.liveHandleCount == 1)
        observer.release()
        #expect(gateway.liveHandleCount == 0)
    }

    @Test("a hotkey whose registration failed is still a live handle until it is released")
    func aFailedHotkeyStillCountsUntilReleased() {
        gateway.script(status: -9878, forID: 1)
        let hotkey = gateway.register(id: 1, keyCode: 80, modifiers: 6912)
        #expect(hotkey.status == -9878)
        #expect(gateway.liveHandleCount == 1)
        hotkey.release()
        #expect(gateway.liveHandleCount == 0)
    }

    @Test("a second release is counted in doubleReleaseCount and does not lower liveHandleCount again")
    func aSecondReleaseIsCounted() {
        let hotkey = gateway.register(id: 1, keyCode: 80, modifiers: 6912)
        let other = gateway.register(id: 2, keyCode: 80, modifiers: 6912)
        hotkey.release()
        hotkey.release()
        #expect(gateway.doubleReleaseCount == 1)
        #expect(gateway.liveHandleCount == 1)
        other.release()
        #expect(gateway.liveHandleCount == 0)
        #expect(gateway.doubleReleaseCount == 1)
    }
}
