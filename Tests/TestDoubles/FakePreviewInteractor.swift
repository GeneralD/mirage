import Domain
import TestSupport

/// `PreviewInteractor` as the presenter suites see it: records the views attached and
/// detached, by identity, and appends `"attach"` or `"detach"` to `order` on every call.
/// While a refusal is set (`init(refusal:)`, or `refuse(with:)` to switch it later), `attach`
/// still appends to `order` but records nothing in `attached` and returns `.refused(refusal)`.
public final class FakePreviewInteractor: PreviewInteractor, Sendable {
    public let attached = Collector<ObjectIdentifier>()
    public let detached = Collector<ObjectIdentifier>()
    public let order = Collector<String>()
    private let refusal: Locked<PreviewRefusal?>

    public init(refusal: PreviewRefusal? = nil) {
        self.refusal = Locked(refusal)
    }

    /// Makes `attach` refuse with `refusal` from now on, or accept again when it is `nil`.
    public func refuse(with refusal: PreviewRefusal?) {
        self.refusal.set(refusal)
    }

    @MainActor
    public func attach(_ target: any PreviewTargetHandle) -> PreviewAttachResult {
        order.append("attach")
        if let refusal = refusal.current { return .refused(refusal) }
        attached.append(ObjectIdentifier(target))
        return .attached
    }

    public func detach(_ target: any PreviewTargetHandle) {
        order.append("detach")
        detached.append(ObjectIdentifier(target))
    }
}
