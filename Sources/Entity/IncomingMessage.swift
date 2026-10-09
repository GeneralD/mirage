/// What one receive on the extension's service port yields. The host's frames
/// are the bulk of it; the other two cases are the presence protocol: the host
/// announces a send right to its presence port (`hello`), and the kernel
/// reports that port's receive right died (`deadName`).
public enum IncomingMessage: Sendable, Hashable {
    case frame(FrameMessage)
    /// The host's presence send right, moved into this process. The receiver
    /// asks for a dead-name notification on it and releases it when done.
    case hello(MachSendRight)
    /// The kernel's dead-name notification: the named right now refers to a
    /// destroyed port (the host exited or disconnected). The receiver releases the name.
    case deadName(MachPortToken)
}
