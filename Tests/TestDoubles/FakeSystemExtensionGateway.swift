import Domain
import TestSupport

/// Activation requests the test answers by hand: `emit` relays a delegate
/// event to the most recent request's stream, `finish` ends it.
public final class FakeSystemExtensionGateway: SystemExtensionGateway, Sendable {
    private let continuation = Locked<AsyncStream<SystemExtensionEvent>.Continuation?>(nil)
    public let activations = Collector<String>()

    public init() {}

    /// The continuation is stored before the activation is recorded, so a test
    /// that waited on `activations` can `emit` straight away without the event
    /// falling into the gap.
    public func activate(extensionBundleID: String) -> AsyncStream<SystemExtensionEvent> {
        let (stream, continuation) = AsyncStream<SystemExtensionEvent>.makeStream()
        self.continuation.set(continuation)
        activations.append(extensionBundleID)
        return stream
    }

    public func emit(_ event: SystemExtensionEvent) {
        continuation.current?.yield(event)
    }

    public func finish() {
        continuation.current?.finish()
    }
}
