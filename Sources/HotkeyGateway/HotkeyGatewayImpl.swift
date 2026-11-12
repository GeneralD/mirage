// Live HotkeyGateway: global hotkeys through the application event target.
// 1:1 over Carbon InstallEventHandler and RegisterEventHotKey (no permission prompt is involved).
import Carbon
import Domain

private let pressed: EventHandlerUPP = { _, event, userData in
    let id = UnsafeMutablePointer<EventHotKeyID>.allocate(capacity: 1)
    defer { id.deallocate() }
    GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, id)
    userData.map { Unmanaged<PressBox>.fromOpaque($0).takeUnretainedValue() }?.onPress(id.pointee.id)
    return noErr
}

public struct HotkeyGatewayImpl: HotkeyGateway {
    public init() {}

    @MainActor
    public func observePresses(_ onPress: @escaping @Sendable (UInt32) -> Void) -> any HotkeyHandle {
        let box = Unmanaged.passRetained(PressBox(onPress))
        let slot = UnsafeMutablePointer<EventHandlerRef?>.allocate(capacity: 1)
        slot.initialize(to: nil)
        let spec = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        let status = InstallEventHandler(GetApplicationEventTarget(), pressed, 1, spec, box.toOpaque(), slot)
        return HandlerHandle(status: status, slot: slot, box: box)
    }

    @MainActor
    public func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> any HotkeyHandle {
        let slot = UnsafeMutablePointer<EventHotKeyRef?>.allocate(capacity: 1)
        slot.initialize(to: nil)
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x6d72_6772, id: id), GetApplicationEventTarget(), 0, slot)
        return HotKeyHandle(status: status, slot: slot)
    }
}
