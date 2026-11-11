import AppKit
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@testable import AppRouter

/// The picker window's half of the live preview (#68): the window tells its preview whether it is on screen,
/// read from the window's own state, and `pickerWindowIsShown` says what counts as on screen. Every window here
/// is made and never shown, so no suite puts a window on screen.
@MainActor
@Suite("EffectPickerWindow: the preview follows the window's visibility", .timeLimit(.minutes(1)))
struct PickerWindowVisibilityTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    @Test("a window counts as shown only when its occlusion state shows it visible and it is not miniaturized")
    func shownOnlyWhenVisibleAndNotMiniaturized() {
        #expect(pickerWindowIsShown(occlusion: [], isMiniaturized: false) == false)
        #expect(pickerWindowIsShown(occlusion: .visible, isMiniaturized: false) == true)
        #expect(pickerWindowIsShown(occlusion: .visible, isMiniaturized: true) == false)
        #expect(pickerWindowIsShown(occlusion: [], isMiniaturized: true) == false)
    }

    @Test("a window that was never shown reports hidden to its preview, which attaches once and detaches once")
    func neverShownWindowDetachesOnce() {
        let interactor = FakePreviewInteractor()
        let preview = withDependencies {
            $0.previewInteractor = interactor
        } operation: {
            PreviewPresenter()
        }
        let window = EffectPickerWindow(presenter: picker(), preview: preview) { _ in }

        preview.start()
        preview.receive(FakePreviewTargetHandle())
        preview.setVisible(true)
        window.windowDidChangeOcclusionState(Notification(name: NSWindow.didChangeOcclusionStateNotification))
        window.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification))
        window.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification))

        #expect(interactor.order.values == ["attach", "detach"], "the window's report hides it once; the repeats change nothing")
    }

    @Test("the live preview window is an EffectPickerWindow over the picker and the preview, and its close reports that window")
    func liveWindowWithPreviewReportsItsClose() {
        let preview = withDependencies {
            $0.previewInteractor = FakePreviewInteractor()
        } operation: {
            PreviewPresenter()
        }
        let closed = Collector<ObjectIdentifier>()

        let window = AppRouter.previewPickerWindow(over: picker(), preview: preview) { closed.append(ObjectIdentifier($0)) }
        // Never shown: closing a window that was never on screen still reports, and puts nothing on screen.
        window.close()

        let reported: [ObjectIdentifier] = closed.values
        #expect(window is EffectPickerWindow)
        #expect(reported == [ObjectIdentifier(window)])
    }

    /// A picker Presenter over one fake catalog, built inside `withDependencies` so it never reaches the live Interactor.
    private func picker() -> EffectPickerPresenter {
        withDependencies {
            $0.effectInteractor = FakeEffectInteractor(state: .fixture([chromatic]))
        } operation: {
            EffectPickerPresenter()
        }
    }
}
