import Domain
import Foundation

@testable import MachGateway

/// One real Mach service: the receive right registered under a unique name and
/// the send right the host would get by looking it up.
struct MachLoopback {
    let bootstrap = MachBootstrapGatewayImpl()
    let messaging = MachMessageGatewayImpl()
    let serviceName: String
    let receive: MachPortToken
    let send: MachPortToken

    init() throws {
        serviceName = "\(ProductIdentity.machServiceName).test.\(getpid()).\(UUID().uuidString)"
        receive = try bootstrap.register(serviceName: serviceName)
        send = try bootstrap.lookUp(serviceName: serviceName)
    }

    /// The next frame on the receive right; any other message shape is a failure.
    func receiveFrame() async throws -> FrameMessage {
        try await messaging.receiveFrame(on: receive)
    }

    func tearDown() {
        bootstrap.deallocate(send)
        bootstrap.destroyReceiveRight(receive)
    }
}

extension MachMessageGatewayImpl {
    func receiveFrame(on port: MachPortToken) async throws -> FrameMessage {
        guard case .frame(let message) = try await receive(on: port) else { throw MachError.malformedMessage }
        return message
    }
}
