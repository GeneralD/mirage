import Domain
import TestSupport

/// `CameraControlUseCase` answering `ensureAuthorized()` with a fixed decision,
/// at once. Counts the asks, and appends `"authorize"` to `order` so a launch
/// sequence that shares the collector with other fakes can be checked for order.
public final class FakeCameraControlUseCase: CameraControlUseCase, Sendable {
    private let decision: CameraAuthorizationStatus
    public let asks = Collector<Void>()
    private let order: Collector<String>

    public init(decision: CameraAuthorizationStatus, order: Collector<String> = Collector()) {
        self.decision = decision
        self.order = order
    }

    public func ensureAuthorized() async -> CameraAuthorizationStatus {
        asks.append(())
        order.append("authorize")
        return decision
    }
}
