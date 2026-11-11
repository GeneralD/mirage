import Combine
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import Presenters

@MainActor
@Suite("PreviewPresenter", .timeLimit(.minutes(1)))
struct PreviewPresenterTests {
    // MARK: - Attach gate

    @Test("nothing is attached before the picker opens, however often the view and the visibility are reported")
    func quietBeforeStart() {
        let rig = PreviewRig()

        rig.presenter.setVisible(true)
        rig.presenter.receive(FakePreviewTargetHandle())
        rig.presenter.setVisible(false)
        rig.presenter.setVisible(true)

        #expect(rig.interactor.order.values.isEmpty)
    }

    @Test("start attaches nothing by itself: the view is attached once it is received while the window is visible")
    func startAloneAttachesNothing() {
        let rig = PreviewRig()
        let target = FakePreviewTargetHandle()

        rig.presenter.start()
        #expect(rig.interactor.order.values.isEmpty)

        rig.presenter.receive(target)
        #expect(rig.interactor.order.values.isEmpty, "the window is not visible yet")

        rig.presenter.setVisible(true)
        #expect(rig.interactor.order.values == ["attach"])
        #expect(rig.interactor.attached.values == [ObjectIdentifier(target)])
    }

    @Test("reporting the same facts again attaches nothing more")
    func repeatedFactsAttachOnce() {
        let rig = PreviewRig()
        let target = FakePreviewTargetHandle()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(target)

        rig.presenter.setVisible(true)
        rig.presenter.receive(target)

        #expect(rig.interactor.order.values == ["attach"])
    }

    @Test("hiding the window detaches the view once, and showing it attaches the same view again in the order attach, detach, attach")
    func hideAndShowAttachAgain() {
        let rig = PreviewRig()
        let target = FakePreviewTargetHandle()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(target)

        rig.presenter.setVisible(false)
        #expect(rig.interactor.detached.values == [ObjectIdentifier(target)])

        rig.presenter.setVisible(true)
        #expect(rig.interactor.order.values == ["attach", "detach", "attach"])
        #expect(rig.interactor.attached.values == [ObjectIdentifier(target), ObjectIdentifier(target)])
    }

    @Test("hiding an already hidden window detaches nothing more")
    func repeatedHideDetachesOnce() {
        let rig = PreviewRig()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(FakePreviewTargetHandle())

        rig.presenter.setVisible(false)
        rig.presenter.setVisible(false)
        rig.presenter.setVisible(false)

        #expect(rig.interactor.order.values == ["attach", "detach"])
    }

    @Test("stop detaches an attached view once and lets go of it, so a visible window attaches nothing until the picker opens and a view arrives")
    func stopLetsGoOfTheView() {
        let rig = PreviewRig()
        let first = FakePreviewTargetHandle()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(first)

        rig.presenter.stop()
        #expect(rig.interactor.order.values == ["attach", "detach"])
        #expect(rig.interactor.detached.values == [ObjectIdentifier(first)])

        rig.presenter.setVisible(true)
        rig.presenter.start()
        #expect(rig.interactor.order.values == ["attach", "detach"], "no view was received since the stop")

        let second = FakePreviewTargetHandle()
        rig.presenter.receive(second)
        #expect(rig.interactor.order.values == ["attach", "detach", "attach"])
        #expect(rig.interactor.attached.values == [ObjectIdentifier(first), ObjectIdentifier(second)])
    }

    @Test("stop with nothing attached calls the Interactor not at all")
    func stopWithoutAnAttachmentCallsNothing() {
        let rig = PreviewRig()
        rig.presenter.start()
        rig.presenter.setVisible(true)

        rig.presenter.stop()

        #expect(rig.interactor.order.values.isEmpty)
    }

    @Test("a view that arrives while another is attached replaces it with an attach and no detach")
    func newViewReplacesTheOld() {
        let rig = PreviewRig()
        let first = FakePreviewTargetHandle()
        let second = FakePreviewTargetHandle()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(first)

        rig.presenter.receive(second)

        #expect(rig.interactor.attached.values == [ObjectIdentifier(first), ObjectIdentifier(second)])
        #expect(rig.interactor.detached.values.isEmpty)
    }

    // MARK: - Refusal

    @Test("a refused view is reported as unavailable and not counted as attached, and showing the window again tries it again")
    func refusalIsReportedAndRetried() {
        let rig = PreviewRig(refusal: .noDevice)
        let target = FakePreviewTargetHandle()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(target)

        #expect(rig.presenter.unavailableMessage == "No GPU is available, so the preview cannot be shown.")
        #expect(rig.interactor.attached.values.isEmpty)

        rig.interactor.refuse(with: nil)
        rig.presenter.setVisible(false)
        rig.presenter.setVisible(true)

        #expect(rig.presenter.unavailableMessage == nil)
        #expect(rig.interactor.attached.values == [ObjectIdentifier(target)])
        #expect(rig.interactor.order.values == ["attach", "attach"])
    }

    @Test("a refused view that is hidden again is not detached, since nothing was attached")
    func refusedViewIsNotDetached() {
        let rig = PreviewRig(refusal: .foreignTarget)
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(FakePreviewTargetHandle())

        rig.presenter.setVisible(false)
        rig.presenter.stop()

        #expect(rig.interactor.order.values == ["attach"])
        #expect(rig.interactor.detached.values.isEmpty)
    }

    @Test("the same facts reported again after a refusal publish no message of their own")
    func repeatedFactsAfterRefusalPublishNothing() {
        let rig = PreviewRig(refusal: .unavailable)
        let target = FakePreviewTargetHandle()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(target)
        let published = Collector<String?>()
        let subscription = rig.presenter.$unavailableMessage.dropFirst().sink { published.append($0) }

        rig.presenter.setVisible(true)
        rig.presenter.receive(target)

        #expect(published.values.isEmpty, "the message did not change")
        #expect(rig.interactor.order.values == ["attach"])
        withExtendedLifetime(subscription) {}
    }

    @Test("stop puts the unavailable message back to nil")
    func stopClearsTheMessage() {
        let rig = PreviewRig(refusal: .unavailable)
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(FakePreviewTargetHandle())
        #expect(rig.presenter.unavailableMessage == "The preview could not start.")

        rig.presenter.stop()

        #expect(rig.presenter.unavailableMessage == nil)
    }

    // MARK: - Mode

    @Test("the mode is .after by default, and it can be chosen while nothing is attached")
    func defaultModeIsAfterAndChoosable() {
        let rig = PreviewRig()

        #expect(rig.presenter.mode == .after)
        #expect(rig.presenter.canChooseMode)
    }

    @Test("a mode chosen before the view is attached sends nothing, and the attach sends .split right after it, in the order attach, setMode")
    func modeChosenBeforeAttachIsSentAfterAttach() {
        let rig = PreviewRig()
        rig.presenter.start()
        rig.presenter.setVisible(true)

        rig.presenter.select(.split)
        #expect(rig.interactor.order.values.isEmpty)

        rig.presenter.receive(FakePreviewTargetHandle())
        #expect(rig.interactor.order.values == ["attach", "setMode"])
        #expect(rig.interactor.modes.values == [.split])
    }

    @Test("a mode chosen while the view is attached is sent once, and choosing the mode already chosen sends nothing")
    func modeChosenWhileAttachedIsSentOnce() {
        let rig = PreviewRig()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(FakePreviewTargetHandle())

        rig.presenter.select(.split)
        #expect(rig.interactor.modes.values == [.split])

        rig.presenter.select(.split)
        #expect(rig.interactor.modes.values == [.split], "the same mode is not sent again")

        rig.presenter.select(.after)
        #expect(rig.interactor.modes.values == [.split, .after])
    }

    @Test("hiding the window in .split sends .after before the detach, and showing it sends .split after the attach")
    func hidingAndShowingSplitResetsAndRestoresIt() {
        let rig = PreviewRig()
        let target = FakePreviewTargetHandle()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(target)
        rig.presenter.select(.split)

        rig.presenter.setVisible(false)
        #expect(rig.interactor.order.values == ["attach", "setMode", "setMode", "detach"])
        #expect(rig.interactor.modes.values == [.split, .after])
        #expect(rig.presenter.mode == .split, "hiding keeps the mode")

        rig.presenter.setVisible(true)
        #expect(rig.interactor.order.values == ["attach", "setMode", "setMode", "detach", "attach", "setMode"])
        #expect(rig.interactor.modes.values == [.split, .after, .split])
    }

    @Test("stopping in .split sends .after before the detach and puts the mode back to .after")
    func stopInSplitResetsBeforeDetach() {
        let rig = PreviewRig()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(FakePreviewTargetHandle())
        rig.presenter.select(.split)

        rig.presenter.stop()

        #expect(rig.interactor.order.values == ["attach", "setMode", "setMode", "detach"])
        #expect(rig.interactor.modes.values == [.split, .after])
        #expect(rig.presenter.mode == .after)
    }

    @Test("stopping in .after sends no setMode at all")
    func stopInAfterSendsNoSetMode() {
        let rig = PreviewRig()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.receive(FakePreviewTargetHandle())

        rig.presenter.stop()

        #expect(rig.interactor.order.values == ["attach", "detach"])
    }

    @Test("a refused attach sends no setMode and makes the mode unchoosable, and a successful attach makes it choosable again")
    func refusedAttachSendsNoModeAndBlocksChoice() {
        let rig = PreviewRig(refusal: .noDevice)
        let target = FakePreviewTargetHandle()
        rig.presenter.start()
        rig.presenter.setVisible(true)
        rig.presenter.select(.split)

        rig.presenter.receive(target)
        #expect(rig.interactor.order.values == ["attach"], "the refused attach sends no setMode")
        #expect(!rig.presenter.canChooseMode)

        rig.interactor.refuse(with: nil)
        rig.presenter.setVisible(false)
        rig.presenter.setVisible(true)
        #expect(rig.presenter.canChooseMode)
        #expect(rig.interactor.order.values == ["attach", "attach", "setMode"])
    }

    // MARK: - Accessibility

    @Test("the accessibility label is the preview's own label")
    func accessibilityLabelIsThePreviewLabel() {
        let rig = PreviewRig()

        #expect(rig.presenter.accessibilityLabel == previewAccessibilityLabel)
    }

    @Test("the mode's title, its accessibility label and the group's label are the PreviewText strings")
    func modeWordingComesFromPreviewText() {
        let rig = PreviewRig()

        for mode in PreviewMode.allCases {
            #expect(rig.presenter.title(of: mode) == previewModeTitle(mode))
            #expect(rig.presenter.accessibilityLabel(of: mode) == previewModeAccessibilityLabel(mode))
        }
        #expect(rig.presenter.modeGroupAccessibilityLabel == previewModeGroupAccessibilityLabel)
    }
}

/// A preview Presenter over a `FakePreviewInteractor` the test inspects, built inside `withDependencies`
/// (the Presenter captures the dependencies of the scope it is made in).
@MainActor
private struct PreviewRig {
    let interactor: FakePreviewInteractor
    let presenter: PreviewPresenter

    init(refusal: PreviewRefusal? = nil) {
        let interactor = FakePreviewInteractor(refusal: refusal)
        self.interactor = interactor
        presenter = withDependencies {
            $0.previewInteractor = interactor
        } operation: {
            PreviewPresenter()
        }
    }
}
