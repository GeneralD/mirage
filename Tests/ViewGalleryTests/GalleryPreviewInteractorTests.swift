import Domain
import Testing

@testable import ViewGallery

/// A view that is never on screen: the preview Interactor sees of it nothing but its identity.
private final class FakePreviewTarget: PreviewTargetHandle, Sendable {
    var backing: AnyObject { self }
}

@MainActor
@Suite("GalleryPreviewInteractor", .timeLimit(.minutes(1)))
struct GalleryPreviewInteractorTests {
    @Test("attach returns the result the Interactor was made with", arguments: [PreviewAttachResult.attached, .refused(.noDevice)])
    func attachReturnsItsResult(result: PreviewAttachResult) {
        let interactor = GalleryPreviewInteractor(result: result)

        #expect(interactor.attach(FakePreviewTarget()) == result)
    }

    @Test(
        "attach still returns the result it was made with after detach and setMode",
        arguments: [PreviewAttachResult.attached, .refused(.noDevice)])
    func attachAfterCommandsReturnsItsResult(result: PreviewAttachResult) {
        let interactor = GalleryPreviewInteractor(result: result)
        let target = FakePreviewTarget()

        interactor.detach(target)
        interactor.setMode(.split)

        #expect(interactor.attach(target) == result)
    }
}
