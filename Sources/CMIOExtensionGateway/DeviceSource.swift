import CoreMediaIO

/// Support for `StreamOutputGatewayImpl` (port: `StreamOutputGateway`).
/// The `CMIOExtensionDeviceSource` (CoreMediaIO) that reports a virtual
/// transport ('virt', the value of `kIOAudioDeviceTransportTypeVirtual`).
final class DeviceSource: NSObject, CMIOExtensionDeviceSource, @unchecked Sendable {
    let availableProperties: Set<CMIOExtensionProperty> = [.deviceTransportType, .deviceModel]
    private let model: String

    init(model: String) {
        self.model = model
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let result = CMIOExtensionDeviceProperties(dictionary: [:])
        result.transportType = properties.contains(.deviceTransportType) ? 0x7669_7274 : nil
        result.model = properties.contains(.deviceModel) ? model : nil
        return result
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}
}
