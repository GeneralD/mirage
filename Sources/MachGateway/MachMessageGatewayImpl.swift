/// Port: MachMessageGateway (type and queue).
/// OS API: a private serial dispatch queue that hosts the blocking mach_msg receive.
/// Kept apart so the file that imports Foundation never names `MachError`, which Foundation also declares.
import Foundation

public final class MachMessageGatewayImpl: Sendable {
    let receiveQueue = DispatchQueue(label: "mach.frame.receive")

    public init() {}
}
