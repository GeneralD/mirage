import Domain
import TestDoubles
import TestSupport

/// `FakeSystemExtensionGateway` plus a "ready" signal raised only after the
/// fake can accept events. The fake records the activation before it stores the
/// stream's continuation, so waiting on its own `activations` can return while
/// an `emit` would still be dropped; `activated` closes that window.
final class AnnouncingGateway: SystemExtensionGateway, Sendable {
    private let fake = FakeSystemExtensionGateway()
    let activated = Collector<Void>()

    var activations: Collector<String> { fake.activations }

    func activate(extensionBundleID: String) -> AsyncStream<SystemExtensionEvent> {
        let stream = fake.activate(extensionBundleID: extensionBundleID)
        activated.append(())
        return stream
    }

    func emit(_ event: SystemExtensionEvent) {
        fake.emit(event)
    }

    func finish() {
        fake.finish()
    }
}
