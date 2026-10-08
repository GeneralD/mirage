import Domain
import TestSupport

/// Activation requests the test answers by hand: `emit` relays a delegate
/// event to the most recent request's stream, `finish` ends it.
public final class FakeSystemExtensionGateway: SystemExtensionGateway, Sendable {
    private let continuation = Locked<AsyncStream<SystemExtensionEvent>.Continuation?>(nil)
    public let activations = Collector<String>()

    public init() {}

    public func activate(extensionBundleID: String) -> AsyncStream<SystemExtensionEvent> {
        activations.append(extensionBundleID)
        let (stream, continuation) = AsyncStream<SystemExtensionEvent>.makeStream()
        self.continuation.set(continuation)
        return stream
    }

    public func emit(_ event: SystemExtensionEvent) {
        continuation.current?.yield(event)
    }

    public func finish() {
        continuation.current?.finish()
    }
}
