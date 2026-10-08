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

    func tearDown() {
        bootstrap.deallocate(send)
        bootstrap.destroyReceiveRight(receive)
    }
}
