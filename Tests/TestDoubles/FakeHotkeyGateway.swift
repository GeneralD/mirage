import Domain
import TestSupport

/// `HotkeyGateway` the test drives by hand: `register` and `observePresses` arm and record, and
/// `press(id:)` delivers a press the way the OS does for a hotkey it still holds. Nothing happens
/// on its own.
///
/// A handle is counted from the moment it is handed out until its one `release()`. `liveHandleCount`
/// is the number not yet released, and `doubleReleaseCount` counts a release of a handle already
/// given back, which the live handle cannot see. A hotkey whose registration was refused (a
/// non-zero status) is still a handle the owner releases, as with the live gateway.
///
/// `script(status:forID:)` and `failObserve(with:)` choose the status the next calls hand back.
/// Like the other fakes that record, a handle is stored before the call is recorded, so a test
/// that waited on `registrations` or `observations` can `press` at once.
public final class FakeHotkeyGateway: HotkeyGateway, @unchecked Sendable {
    public struct Registration: Sendable, Equatable {
        public let id: UInt32
        public let keyCode: UInt32
        public let modifiers: UInt32

        public init(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
            self.id = id
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    private struct Observer {
        let onPress: @Sendable (UInt32) -> Void
        let status: Int32
        var isReleased = false
    }

    private struct Hotkey {
        let id: UInt32
        let status: Int32
        var isReleased = false
    }

    fileprivate enum Slot: Sendable {
        case observer(Int)
        case hotkey(Int)
    }

    private struct State {
        var observers: [Observer] = []
        var hotkeys: [Hotkey] = []
        var scriptedStatus: [UInt32: Int32] = [:]
        var observeStatus: Int32 = 0
        var doubleReleaseCount = 0
    }

    private let state = Locked(State())
    /// Every `register` call, in order, whether or not the OS would have accepted it.
    public let registrations = Collector<Registration>()
    /// Every `observePresses` call, in order.
    public let observations = Collector<Void>()

    public init() {}

    // MARK: Hooks

    /// Makes `register` of `id` hand back a handle with `status` from now on; `0` is success and the default.
    public func script(status: Int32, forID id: UInt32) {
        state.withLock { $0.scriptedStatus[id] = status }
    }

    /// Makes `observePresses` hand back a handle with `status` from now on; `0` is success and the default.
    public func failObserve(with status: Int32) {
        state.withLock { $0.observeStatus = status }
    }

    /// The handles handed out and not yet released, observers and hotkeys alike.
    public var liveHandleCount: Int {
        state.withLock { state in
            state.observers.filter { !$0.isReleased }.count + state.hotkeys.filter { !$0.isReleased }.count
        }
    }

    /// Releases of a handle that had already been released.
    public var doubleReleaseCount: Int {
        state.withLock { $0.doubleReleaseCount }
    }

    /// Delivers a press of `id` on the calling thread to every observer not yet released, and says
    /// whether there was one. It delivers nothing and returns `false` unless a registration of `id`
    /// is not released and has status `0`, which is what the OS does for a hotkey it still holds.
    @MainActor
    public func press(id: UInt32) -> Bool {
        let listeners = state.withLock { state -> [@Sendable (UInt32) -> Void] in
            guard state.hotkeys.contains(where: { !$0.isReleased && $0.id == id && $0.status == 0 }) else { return [] }
            return state.observers.filter { !$0.isReleased }.map(\.onPress)
        }
        for listener in listeners { listener(id) }
        return !listeners.isEmpty
    }

    // MARK: HotkeyGateway

    @MainActor
    public func observePresses(_ onPress: @escaping @Sendable (UInt32) -> Void) -> any HotkeyHandle {
        let (slot, status) = state.withLock { state -> (Slot, Int32) in
            state.observers.append(Observer(onPress: onPress, status: state.observeStatus))
            return (.observer(state.observers.count - 1), state.observeStatus)
        }
        observations.append(())
        return Handle(gateway: self, slot: slot, status: status)
    }

    @MainActor
    public func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> any HotkeyHandle {
        let (slot, status) = state.withLock { state -> (Slot, Int32) in
            let status = state.scriptedStatus[id] ?? 0
            state.hotkeys.append(Hotkey(id: id, status: status))
            return (.hotkey(state.hotkeys.count - 1), status)
        }
        registrations.append(Registration(id: id, keyCode: keyCode, modifiers: modifiers))
        return Handle(gateway: self, slot: slot, status: status)
    }

    fileprivate func release(_ slot: Slot) {
        state.withLock { state in
            switch slot {
            case .observer(let index):
                guard !state.observers[index].isReleased else {
                    state.doubleReleaseCount += 1
                    return
                }
                state.observers[index].isReleased = true
            case .hotkey(let index):
                guard !state.hotkeys[index].isReleased else {
                    state.doubleReleaseCount += 1
                    return
                }
                state.hotkeys[index].isReleased = true
            }
        }
    }

    private final class Handle: HotkeyHandle, @unchecked Sendable {
        let status: Int32
        private let gateway: FakeHotkeyGateway
        private let slot: Slot

        init(gateway: FakeHotkeyGateway, slot: Slot, status: Int32) {
            self.gateway = gateway
            self.slot = slot
            self.status = status
        }

        @MainActor
        func release() {
            gateway.release(slot)
        }
    }
}
