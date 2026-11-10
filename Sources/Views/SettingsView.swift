import Presenters
import SwiftUI

/// The settings window (#198), drawn from a `SettingsPresenter`: the launch-at-login switch and its
/// note, the global hotkeys with their rows and note, and the reset-all button with its confirmation.
/// It maps the Presenter's values to controls and decides nothing: which switch is on, which note
/// shows, which hotkeys are listed, and whether a reset is running are the Presenter's. The two
/// switches write through the Presenter, and the switch moves when the state comes back with the change.
public struct SettingsView: View {
    @ObservedObject private var presenter: SettingsPresenter

    public init(presenter: SettingsPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: launchAtLogin)
                    .disabled(!presenter.canChangeLaunchAtLogin)
                if let note = presenter.launchAtLoginNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if presenter.canOpenLoginItemsSettings {
                    Button("Open Login Items Settings…") { presenter.openLoginItemsSettings() }
                }
            }
            Section("Hotkeys") {
                Toggle("Enable Global Hotkeys", isOn: hotkeys)
                ForEach(presenter.hotkeyRows) { row in
                    LabeledContent(row.title, value: row.keys)
                        .foregroundStyle(presenter.hotkeysEnabled ? .primary : .secondary)
                }
                if let note = presenter.hotkeyNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Reset All Settings…", role: .destructive) { presenter.requestReset() }
                    .disabled(presenter.isResetting)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .confirmationDialog("Reset all settings?", isPresented: $presenter.isConfirmingReset) {
            Button("Reset", role: .destructive) { presenter.confirmReset() }
        } message: {
            Text("The chosen effect and every other stored setting go back to their defaults. Launch at login is turned off.")
        }
    }

    // The closures are assumed to be on the main actor, as `EffectMenu`'s bindings assume: SwiftUI
    // calls them from the main thread, and the Presenter is main-actor isolated.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { MainActor.assumeIsolated { presenter.launchesAtLogin } },
            set: { on in MainActor.assumeIsolated { presenter.setLaunchAtLogin(on) } })
    }

    private var hotkeys: Binding<Bool> {
        Binding(
            get: { MainActor.assumeIsolated { presenter.hotkeysEnabled } },
            set: { on in MainActor.assumeIsolated { presenter.setHotkeysEnabled(on) } })
    }
}
