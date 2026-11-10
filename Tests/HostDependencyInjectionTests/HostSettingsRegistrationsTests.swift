import Dependencies
import Domain
import HotkeyGateway
import LoginItemDataSource
import LoginItemGateway
import SettingsUseCase
import StoreMaintenanceDataStore
import Testing

/// The host registers the live value of each stateless port of the settings graph (#192): the hotkey
/// gateway, the login item gateway and data source, the store maintenance and the settings use case.
/// They hold nothing between calls, so resolving each one inside `withDependencies { $0.context = .live }`,
/// with no override, checks the registration itself.
///
/// The stateful ports (`controlsInteractor`, `settingsInteractor`, `hotkeys`) are not resolved here: a live
/// value keeps the scope that built it for the life of the process, so only `HarnessLiveWiringTests`
/// resolves them, with the harness fakes.
@Suite("Host registrations of the settings graph", .timeLimit(.minutes(1)))
struct HostSettingsRegistrationsTests {
    @Test("the live hotkey gateway is HotkeyGatewayImpl")
    func hotkeyGatewayIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.hotkeyGateway) var hotkeyGateway

            #expect(hotkeyGateway is HotkeyGatewayImpl)
        }
    }

    @Test("the live login item gateway is LoginItemGatewayImpl")
    func loginItemGatewayIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.loginItemGateway) var loginItemGateway

            #expect(loginItemGateway is LoginItemGatewayImpl)
        }
    }

    @Test("the live login item data source is LoginItemDataSourceImpl")
    func loginItemIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.loginItem) var loginItem

            #expect(loginItem is LoginItemDataSourceImpl)
        }
    }

    @Test("the live store maintenance is StoreMaintenanceDataStoreImpl")
    func storeMaintenanceIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.storeMaintenance) var storeMaintenance

            #expect(storeMaintenance is StoreMaintenanceDataStoreImpl)
        }
    }

    @Test("the live settings use case is SettingsUseCaseImpl")
    func settingsUseCaseIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.settingsUseCase) var settingsUseCase

            #expect(settingsUseCase is SettingsUseCaseImpl)
        }
    }
}
