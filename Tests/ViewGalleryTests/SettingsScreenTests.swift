import AppRouter
import Domain
import TestSupport
import Testing

@testable import ViewGallery

/// A settings window that is never on screen: it only counts what the Router asks of it.
@MainActor
private final class FakeSettingsWindow {
    private(set) var shows = 0
    private(set) var closes = 0
}

extension FakeSettingsWindow: SettingsWindow {
    func show() {
        shows += 1
    }

    func close() {
        closes += 1
    }
}

@MainActor
@Suite("Settings screens", .timeLimit(.minutes(1)))
struct SettingsScreenTests {
    @Test("the two settings screens are registered in the gallery once each, under the names settings and settings-attention")
    func registered() {
        let names = galleryScreens.map(\.name)

        #expect(names.filter { $0 == "settings" }.count == 1)
        #expect(names.filter { $0 == "settings-attention" }.count == 1)
    }

    @Test("each settings screen's summary is one line that says what it shows")
    func summaries() {
        let summaries = Dictionary(uniqueKeysWithValues: galleryScreens.map { ($0.name, $0.summary) })

        #expect(summaries["settings"] == "Settings: launch at login on, global hotkeys registered")
        #expect(summaries["settings-attention"] == "Settings: login item awaiting approval, a hotkey in conflict")
    }

    @Test("opening the settings screen makes one window, shows it once, never closes it, and its Presenter reads launch at login as on")
    func opensOneWindow() async throws {
        let windows = Collector<FakeSettingsWindow>()

        let router = openSettings(showing: settingsState) { _, _ in
            let window = FakeSettingsWindow()
            windows.append(window)
            return window
        }

        let window = try #require(windows.values.first)
        #expect(windows.count == 1)
        #expect(window.shows == 1)
        #expect(window.closes == 0)
        await settle(router.settingsPresenter.$launchesAtLogin) { $0 }
        #expect(router.settingsPresenter.launchesAtLogin == true)
    }

    @Test("settings-attention shows a launch-at-login note and a hotkey note, offers the Login Items button, and names Toggle Bypass")
    func attentionNotes() async throws {
        let router = openSettings(showing: settingsAttentionState) { _, _ in FakeSettingsWindow() }
        await settle(router.settingsPresenter.$launchAtLoginNote) { $0 != nil }
        await settle(router.settingsPresenter.$hotkeyNote) { $0 != nil }

        #expect(router.settingsPresenter.launchAtLoginNote != nil)
        #expect(router.settingsPresenter.canOpenLoginItemsSettings == true)
        let hotkeyNote = try #require(router.settingsPresenter.hotkeyNote)
        #expect(hotkeyNote.contains("Toggle Bypass"))
    }
}
