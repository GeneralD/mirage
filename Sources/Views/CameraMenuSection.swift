import Domain
import Presenters
import SwiftUI

/// The contents of the camera menu (epic E5-camera, #168), drawn from a `CameraMenuPresenter`. The menu's own
/// `Menu(presenter.title)` wraps it (#170); here it is the vertical list inside that menu. It maps the
/// Presenter's values to menu items and decides nothing: the status line, the cameras, their order, which one
/// is checked, which submenu is disabled and the mirror flag are all the Presenter's.
///
/// Like `EffectMenu`, a `Toggle` is an item whose `state` is `.on` for the checked row, so the titles line up in
/// the state column, and a bare `Text` is a disabled item. The resolution and frame-rate lists are submenus.
public struct CameraMenuSection: View {
    @ObservedObject private var presenter: CameraMenuPresenter

    public init(presenter: CameraMenuPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if let status = presenter.status {
            Text(status)
            Divider()
        }
        if !presenter.devices.isEmpty {
            ForEach(presenter.devices) { option in
                choiceRow(option, select: presenter.selectDevice)
            }
            Divider()
        }
        Menu(presenter.resolutionTitle) {
            ForEach(presenter.resolutions) { option in
                choiceRow(option, select: presenter.selectResolution)
            }
        }
        .disabled(presenter.resolutions.isEmpty)
        Menu(presenter.frameRateTitle) {
            ForEach(presenter.frameRates) { option in
                choiceRow(option, select: presenter.selectFrameRate)
            }
        }
        .disabled(presenter.frameRates.isEmpty)
        Divider()
        Toggle(presenter.mirrorTitle, isOn: mirrorBinding)
    }

    /// One choice row. Whatever the toggle is flipped to, the user asked for this option: the new value is
    /// ignored, and the Presenter's `isSelected` stays the only truth about what is checked (choosing the
    /// checked row asks for the option that is already in effect).
    private func choiceRow(_ option: CameraMenuOption, select: @escaping @MainActor (String) -> Void) -> some View {
        // Whether `Binding`'s closures are main-actor isolated depends on the SDK, as `EffectMenu.row` notes, so the
        // call is assumed to be on the main actor rather than made from there.
        let isSelected = Binding(
            get: { option.isSelected },
            set: { _ in MainActor.assumeIsolated { select(option.id) } })
        return Toggle(option.title, isOn: isSelected)
    }

    /// The mirror toggle: its value is the Presenter's `isMirrored`, and a flip is handed to `setMirrored`.
    private var mirrorBinding: Binding<Bool> {
        let presenter = self.presenter
        return Binding(
            get: { MainActor.assumeIsolated { presenter.isMirrored } },
            set: { isMirrored in MainActor.assumeIsolated { presenter.setMirrored(isMirrored) } })
    }
}
