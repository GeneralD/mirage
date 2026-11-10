// Live LoginItemGateway: the app as a login item.
// 1:1 over ServiceManagement SMAppService.mainApp (status, register, unregister) and openSystemSettingsLoginItems.
import Domain
import ServiceManagement

public struct LoginItemGatewayImpl: LoginItemGateway {
    public init() {}

    public func rawStatus() -> Int {
        SMAppService.mainApp.status.rawValue
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
