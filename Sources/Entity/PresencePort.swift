/// The host's liveness beacon: a receive right the host keeps for as long as it
/// is connected, plus a send right on it that is handed to the extension. When
/// the host dies (or destroys the receive right) the extension's send right
/// turns into a dead name and a notification arrives.
public struct PresencePort: Sendable, Hashable {
    public let receive: MachPortToken
    public let send: MachSendRight

    public init(receive: MachPortToken, send: MachSendRight) {
        self.receive = receive
        self.send = send
    }
}
