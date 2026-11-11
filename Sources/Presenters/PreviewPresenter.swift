import Combine
import Dependencies
import Domain

/// The display state of the live preview pane in the picker's window: the message that says why the
/// preview is not shown when the pipeline refused its view. It decides when the pipeline's preview is
/// attached to the pane's view and when it is detached, and nothing else: drawing the frames is the
/// view's job, and the pipeline's.
///
/// The attach is gated on three facts the host sends: the picker is open (`start()` and `stop()`), its
/// window is visible (`setVisible(_:)`) and the pane's view exists (`receive(_:)`). Ending is
/// unconditional: `stop()` and a hidden window detach at once. Starting needs all three facts, so a
/// `true` from before is never carried into the next opening.
@MainActor
public final class PreviewPresenter: ObservableObject {
    /// What the pane says in place of the preview when the pipeline refused its view; `nil` while the
    /// view is attached, or nothing was refused.
    @Published public private(set) var unavailableMessage: String?

    @Dependency(\.previewInteractor) private var interactor
    private var isOpen = false
    private var isVisible = false
    /// The pane's view, as the host last handed it over; `nil` before it exists or after `stop()`.
    private var target: (any PreviewTargetHandle)?
    /// The view the pipeline accepted; `nil` when none is attached, including after a refusal.
    private var attachedTarget: (any PreviewTargetHandle)?

    public init() {}

    /// What the pane is called for accessibility.
    public var accessibilityLabel: String { previewAccessibilityLabel }

    /// The picker opened. Calling it again while open does nothing.
    public func start() {
        guard !isOpen else { return }
        isOpen = true
        reconcile()
    }

    /// The picker closed: detaches the view if one is attached, and forgets the view and the window's
    /// visibility, so the next opening does not begin from a stale `true`.
    public func stop() {
        isOpen = false
        isVisible = false
        target = nil
        reconcile()
        showUnavailable(nil)
    }

    /// The pane's view exists. Receiving the same view again does nothing.
    public func receive(_ target: any PreviewTargetHandle) {
        guard self.target !== target else { return }
        self.target = target
        reconcile()
    }

    /// The window became visible or hidden. Reporting the state it already has does nothing.
    public func setVisible(_ isVisible: Bool) {
        guard self.isVisible != isVisible else { return }
        self.isVisible = isVisible
        reconcile()
    }

    /// Makes the attachment match the facts. When the preview is wanted and the attached view is not this
    /// one, it attaches; when it is not wanted, it detaches the attached view. A new view replaces the
    /// attached one with an attach alone: the pipeline keeps the last view it was given.
    private func reconcile() {
        guard previewIsWanted(isOpen: isOpen, isVisible: isVisible, hasTarget: target != nil), let target else {
            detachAttached()
            return
        }
        guard attachedTarget !== target else { return }
        attach(target)
    }

    private func attach(_ target: any PreviewTargetHandle) {
        switch interactor.attach(target) {
        case .attached:
            showUnavailable(nil)
            attachedTarget = target
        case .refused(let refusal):
            showUnavailable(previewUnavailableMessage(for: refusal))
            attachedTarget = nil
        }
    }

    private func detachAttached() {
        guard let attachedTarget else { return }
        self.attachedTarget = nil
        interactor.detach(attachedTarget)
    }

    /// Publishes `message` only when it differs from the one shown, so a repeated refusal does not notify.
    private func showUnavailable(_ message: String?) {
        if unavailableMessage != message { unavailableMessage = message }
    }
}
