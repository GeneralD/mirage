import AppKit
import Domain
import Presenters
import SwiftUI

/// The effects menu (epic #42, D8), drawn from a `MenuBarPresenter`. One declaration serves
/// both places that show it: the `MenuBarExtra(.menu)` of the host app and the
/// `NSHostingMenu` in the dev harness's main menu. It maps the Presenter's values to menu
/// items and decides nothing: the rows, their order, which one is checked, which one is
/// disabled and the status line are all the Presenter's.
///
/// SwiftUI turns this content into `NSMenuItem`s (checked with `NSHostingMenu`): a `Toggle`
/// is an item whose `state` is `.on` for the checked row, so every title lines up in the state
/// column; two `Text`s in one label are an item's title and its `subtitle` (macOS 14.4+, and not
/// drawn on macOS 14 for an attributed title: `docs/ARCHITECTURE.md` → *Menu bar*); a bare `Text`
/// is a disabled item. A `Button` with a checkmark image would put the mark in the image column
/// instead and leave `state` off.
public struct EffectMenu: View {
    @ObservedObject private var presenter: MenuBarPresenter

    public init(presenter: MenuBarPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        ForEach(presenter.items) { item in
            row(item)
        }
        Divider()
        if let status = presenter.status {
            Text(status)
        }
        Button("Open Effects Folder…") { presenter.openEffectsFolder() }
        Divider()
        Button("Quit \(ProductIdentity.displayName)") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// One row. Whatever the toggle is flipped to, the user asked for this effect: the new value
    /// is ignored, and the Presenter's `isSelected` stays the only truth about what is checked
    /// (choosing the checked row asks for the effect that is already chosen).
    private func row(_ item: EffectMenuItem) -> some View {
        let presenter = presenter
        // Whether `Binding`'s closures are main-actor isolated depends on the SDK (the macOS 26 SDK
        // takes a direct call; the older toolchain that builds the release may not), so the call is
        // assumed to be on the main actor rather than made from there: SwiftUI runs a menu item's
        // action on the main thread.
        let isSelected = Binding(
            get: { item.isSelected },
            set: { _ in MainActor.assumeIsolated { presenter.select(item.id) } })
        return Toggle(isOn: isSelected) {
            Text(item.title)
            if let detail = item.detail {
                Text(detail)
            }
        }
        .disabled(!item.isEnabled)
    }
}
