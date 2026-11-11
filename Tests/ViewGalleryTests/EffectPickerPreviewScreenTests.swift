import AppRouter
import Domain
import Presenters
import TestSupport
import Testing

@testable import ViewGallery

/// A picker window that is never on screen: it only counts what the Router asks of it.
@MainActor
private final class FakePreviewPickerWindow {
    private(set) var shows = 0
    private(set) var closes = 0
}

extension FakePreviewPickerWindow: PickerWindow {
    func show() {
        shows += 1
    }

    func close() {
        closes += 1
    }
}

/// A view that is never on screen: the preview pane hands the Router's Presenter nothing but its identity.
private final class FakePreviewTarget: PreviewTargetHandle, Sendable {
    var backing: AnyObject { self }
}

/// Opens a preview screen with a fake window in place of the live one, and returns the Router with the fake windows it made.
@MainActor
private func openPreviewScreen(
    attaching result: PreviewAttachResult, mode: PreviewMode = .after
) -> (router: AppRouter, windows: Collector<FakePreviewPickerWindow>) {
    let windows = Collector<FakePreviewPickerWindow>()
    let router = openEffectPickerPreview(showing: effectPickerCatalog, attaching: result, mode: mode) { _, _, _ in
        let window = FakePreviewPickerWindow()
        windows.append(window)
        return window
    }
    return (router, windows)
}

/// What the live window does once it is on screen: the pane's view exists and the window is visible.
@MainActor
private func showPane(_ preview: PreviewPresenter) {
    preview.receive(FakePreviewTarget())
    preview.setVisible(true)
}

@MainActor
@Suite("Effect picker preview screens", .timeLimit(.minutes(1)))
struct EffectPickerPreviewScreenTests {
    @Test("the three preview screens are registered in the gallery under their names")
    func registered() {
        let names = galleryScreens.map(\.name)

        #expect(names.contains("effect-picker-preview"))
        #expect(names.contains("effect-picker-preview-split"))
        #expect(names.contains("effect-picker-preview-refused"))
    }

    @Test("opening a preview screen makes one window over the picker, shows it once and closes none")
    func opensOneWindow() throws {
        let (_, windows) = openPreviewScreen(attaching: .attached)

        let window = try #require(windows.values.first)
        #expect(windows.count == 1)
        #expect(window.shows == 1)
        #expect(window.closes == 0)
    }

    @Test("the preview pane attaches once its view exists and the window is visible, then shows no message, takes a mode and has After chosen")
    func attachedPane() throws {
        let (router, _) = openPreviewScreen(attaching: .attached)
        let preview = try #require(router.previewPresenter)

        showPane(preview)

        #expect(preview.unavailableMessage == nil)
        #expect(preview.canChooseMode)
        #expect(preview.mode == .after)
    }

    @Test("opening in Split leaves the preview Presenter in Split right after the picker opens")
    func opensInSplit() throws {
        let (router, _) = openPreviewScreen(attaching: .attached, mode: .split)
        let preview = try #require(router.previewPresenter)

        #expect(preview.mode == .split)
    }

    @Test("a refused preview says why in place of the pane and takes no mode, once its view exists and the window is visible")
    func refusedPane() throws {
        let (router, _) = openPreviewScreen(attaching: .refused(.noDevice))
        let preview = try #require(router.previewPresenter)

        showPane(preview)

        #expect(preview.unavailableMessage == "No GPU is available, so the preview cannot be shown.")
        #expect(preview.canChooseMode == false)
    }
}
