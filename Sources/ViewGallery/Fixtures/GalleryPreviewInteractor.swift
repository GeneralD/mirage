import Domain

/// The `PreviewInteractor` the preview screens draw from: `attach` answers the one result it was made with, and `detach` and
/// `setMode` do nothing. A screen shows a state; it does not move it. It is not a test double (`Sources` may not use `TestDoubles`),
/// and no shipped product links this module.
struct GalleryPreviewInteractor {
    let result: PreviewAttachResult
}

extension GalleryPreviewInteractor: PreviewInteractor {
    @MainActor func attach(_ target: any PreviewTargetHandle) -> PreviewAttachResult {
        result
    }

    func detach(_ target: any PreviewTargetHandle) {}

    func setMode(_ mode: PreviewMode) {}
}
