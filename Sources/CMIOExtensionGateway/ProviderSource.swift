import CoreMediaIO
import Domain

/// Support for `StreamOutputGatewayImpl` (port: `StreamOutputGateway`).
/// The `CMIOExtensionProviderSource` (CoreMediaIO) that names the manufacturer.
final class ProviderSource: NSObject, CMIOExtensionProviderSource, @unchecked Sendable {
    let availableProperties: Set<CMIOExtensionProperty> = [.providerManufacturer]

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let result = CMIOExtensionProviderProperties(dictionary: [:])
        result.manufacturer = properties.contains(.providerManufacturer) ? ProductIdentity.displayName : nil
        return result
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
