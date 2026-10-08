/// An opaque Mach port name owned by this process: the send right to the
/// extension's service port (host side, from a look-up) or the receive right
/// for it (extension side, from a check-in or registration). Only the Mach
/// gateway interprets the name.
public struct MachPortToken: Sendable, Hashable {
    public let name: UInt32

    public init(name: UInt32) {
        self.name = name
    }
}

/// A send right that references one surface (`IOSurfaceCreateMachPort`). It is
/// moved into the frame message on send and consumed by the receiver's lookup;
/// whoever holds it last deallocates it.
public struct MachSendRight: Sendable, Hashable {
    public let name: UInt32

    public init(name: UInt32) {
        self.name = name
    }
}
