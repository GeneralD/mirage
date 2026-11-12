// Live handles of HotkeyGateway: what the Carbon calls allocate, given back by `release()`.
// 1:1 over InstallEventHandler / RemoveEventHandler and RegisterEventHotKey / UnregisterEventHotKey.
import Carbon
import Domain

final class PressBox: @unchecked Sendable {
    let onPress: @Sendable (UInt32) -> Void
    init(_ onPress: @escaping @Sendable (UInt32) -> Void) { self.onPress = onPress }
}

final class HandlerHandle: HotkeyHandle, @unchecked Sendable {
    let status: Int32
    private let slot: UnsafeMutablePointer<EventHandlerRef?>
    private let box: Unmanaged<PressBox>
    init(status: Int32, slot: UnsafeMutablePointer<EventHandlerRef?>, box: Unmanaged<PressBox>) {
        self.status = status
        self.slot = slot
        self.box = box
    }
    @MainActor func release() {
        RemoveEventHandler(slot.pointee)
        slot.deallocate()
        box.release()
    }
}

final class HotKeyHandle: HotkeyHandle, @unchecked Sendable {
    let status: Int32
    private let slot: UnsafeMutablePointer<EventHotKeyRef?>
    init(status: Int32, slot: UnsafeMutablePointer<EventHotKeyRef?>) {
        self.status = status
        self.slot = slot
    }
    @MainActor func release() {
        UnregisterEventHotKey(slot.pointee)
        slot.deallocate()
    }
}
