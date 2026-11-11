import AppRouter
import Dependencies
import Domain
import Foundation

extension GalleryScreen {
    /// The picker with its live preview pane over the chosen bundled effect, After chosen: the pipeline accepts the pane's view.
    static var effectPickerPreview: GalleryScreen {
        GalleryScreen(name: "effect-picker-preview", summary: "Effect picker with the live preview pane, After chosen") {
            openEffectPickerPreview(showing: effectPickerCatalog, attaching: .attached, mode: .after)
        }
    }

    /// The same picker with Split chosen, so the segmented control shows the comparison mode.
    static var effectPickerPreviewSplit: GalleryScreen {
        GalleryScreen(name: "effect-picker-preview-split", summary: "Effect picker with the live preview pane, Split chosen") {
            openEffectPickerPreview(showing: effectPickerCatalog, attaching: .attached, mode: .split)
        }
    }

    /// The same picker where the pipeline refused the pane's view for want of a GPU: the pane says why and the mode cannot be chosen.
    static var effectPickerPreviewRefused: GalleryScreen {
        GalleryScreen(
            name: "effect-picker-preview-refused",
            summary: "Effect picker with the live preview pane, the preview could not start (no GPU)"
        ) {
            openEffectPickerPreview(showing: effectPickerCatalog, attaching: .refused(.noDevice), mode: .after)
        }
    }
}

/// Builds an `AppRouter` whose picker shows the live preview pane over `catalog`, where the pipeline's answer to the pane's view is
/// `result`, then chooses `mode` and opens the picker, and answers the Router, which keeps the window alive. The Router is made inside
/// `withDependencies` because its Presenters capture the dependencies of the scope they are built in. `makePreviewPickerWindow` is the
/// seam a test uses to open no real window.
@MainActor
func openEffectPickerPreview(
    showing catalog: EffectCatalogState,
    attaching result: PreviewAttachResult,
    mode: PreviewMode = .after,
    makePreviewPickerWindow: @escaping AppRouter.PreviewPickerWindowFactory = AppRouter.previewPickerWindow(over:preview:onClose:)
) -> AppRouter {
    let router = withDependencies {
        $0.effectInteractor = GalleryEffectInteractor(catalog: catalog)
        $0.previewInteractor = GalleryPreviewInteractor(result: result)
    } operation: {
        AppRouter(showsPreview: true, makePreviewPickerWindow: makePreviewPickerWindow)
    }
    router.previewPresenter?.select(mode)
    router.openEffectPicker()
    return router
}
