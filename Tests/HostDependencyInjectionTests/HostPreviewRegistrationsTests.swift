import Dependencies
import Domain
import Testing

/// The host registers the live value of the preview interactor (#238): a `PreviewInteractorImpl`
/// from the camera interactor module. This suite does not link that module, so it compares the
/// type's name. It resolves nothing else, and nothing is overridden: the live value is built from
/// nothing but its module.
@Suite("Host registrations of the preview", .timeLimit(.minutes(1)))
struct HostPreviewRegistrationsTests {
    @Test("the preview interactor's live value is PreviewInteractorImpl")
    func previewInteractorLiveIsItsImplementation() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.previewInteractor) var previewInteractor

            #expect(String(describing: type(of: previewInteractor)) == "PreviewInteractorImpl")
        }
    }
}
