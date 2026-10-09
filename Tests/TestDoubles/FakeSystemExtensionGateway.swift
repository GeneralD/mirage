import Domain
import TestSupport

/// Activation requests the test answers by hand: `emit` relays a delegate
/// event to a request's stream (the most recent one by default), `finish` ends it.
public final class FakeSystemExtensionGateway: SystemExtensionGateway, Sendable {
    private let continuations = Locked<[AsyncStream<SystemExtensionEvent>.Continuation]>([])
    public let activations = Collector<String>()

    public init() {}

    /// The continuation is stored before the activation is recorded, so a test
    /// that waited on `activations` can `emit` straight away without the event
    /// falling into the gap.
    public func activate(extensionBundleID: String) -> AsyncStream<SystemExtensionEvent> {
        let (stream, continuation) = AsyncStream<SystemExtensionEvent>.makeStream()
        continuations.withLock { $0.append(continuation) }
        activations.append(extensionBundleID)
        return stream
    }

    /// Relays `event` to request number `request` (0-based), or the latest one when omitted.
    public func emit(_ event: SystemExtensionEvent, request: Int? = nil) {
        continuation(of: request)?.yield(event)
    }

    public func finish(request: Int? = nil) {
        continuation(of: request)?.finish()
    }

    private func continuation(of request: Int?) -> AsyncStream<SystemExtensionEvent>.Continuation? {
        let all = continuations.current
        return request.map { all.indices.contains($0) ? all[$0] : nil } ?? all.last
    }
}
