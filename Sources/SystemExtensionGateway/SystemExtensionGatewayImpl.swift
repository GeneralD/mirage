/// Live `SystemExtensionGateway`: one `OSSystemExtensionRequest` activation
/// per call, relayed as an `AsyncStream` of events. Wraps SystemExtensions.
/// Thin by rule: every decision lives in `ExtensionInstallDataSourceImpl`.
import Domain
import SystemExtensions

public struct SystemExtensionGatewayImpl: Sendable {
    public init() {}
}

extension SystemExtensionGatewayImpl: SystemExtensionGateway {
    public func activate(extensionBundleID: String) -> AsyncStream<SystemExtensionEvent> {
        let (stream, continuation) = AsyncStream<SystemExtensionEvent>.makeStream()
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionBundleID, queue: .main)
        let delegate = ActivationRequestDelegate(continuation: continuation)
        request.delegate = delegate
        // The request only holds its delegate weakly; this capture keeps it alive until the stream terminates.
        continuation.onTermination = { _ in _ = delegate }
        OSSystemExtensionManager.shared.submitRequest(request)
        return stream
    }
}
