import Dependencies
import Presenters
import TestDoubles
import TestSupport
import Testing

@testable import AppRouter

/// The settings window's glue (#198): its title, and its close, which reports the window to the Router
/// whether it was shown or not. Every window here is made over a `SettingsPresenter` whose Interactor is a
/// `FakeSettingsInteractor`, so no suite starts the Presenter or resolves the live Interactor.
@MainActor
@Suite("SettingsPanelWindow", .timeLimit(.minutes(1)))
struct SettingsPanelWindowTests {
    @Test("the window is titled Settings, and making it does not report a close")
    func titledAndSilentWhenMade() {
        let closed = Collector<ObjectIdentifier>()

        let window = makeWindow { closed.append(ObjectIdentifier($0)) }

        #expect(window.windowTitle == "Settings")
        #expect(closed.values.isEmpty)
    }

    @Test("close() reports the window once, as itself, even when it was never shown")
    func closeReportsOnceAsItself() {
        let closed = Collector<ObjectIdentifier>()
        let window = makeWindow { closed.append(ObjectIdentifier($0)) }

        window.close()

        #expect(closed.values == [ObjectIdentifier(window)])
    }

    @Test("SettingsPanelWindow can be used as any SettingsWindow, and closing it through the protocol reports it")
    func usableAsSettingsWindow() {
        let closed = Collector<ObjectIdentifier>()
        let window: any SettingsWindow = makeWindow { closed.append(ObjectIdentifier($0)) }

        window.close()

        #expect(closed.values == [ObjectIdentifier(window)])
    }
}

/// A settings window over a Presenter built inside `withDependencies`, so it never reaches the live Interactor.
@MainActor
private func makeWindow(onClose: @escaping @MainActor (SettingsPanelWindow) -> Void) -> SettingsPanelWindow {
    let presenter = withDependencies {
        $0.settingsInteractor = FakeSettingsInteractor()
    } operation: {
        SettingsPresenter()
    }
    return SettingsPanelWindow(presenter: presenter, onClose: onClose)
}
