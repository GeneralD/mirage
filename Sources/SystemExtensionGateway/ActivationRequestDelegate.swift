/// Delegate side of `SystemExtensionGatewayImpl`: translates
/// `OSSystemExtensionRequestDelegate` callbacks into `SystemExtensionEvent`s.
/// Wraps SystemExtensions; it is an `NSObject` because the protocol demands it.
import Domain
import SystemExtensions

final class ActivationRequestDelegate: NSObject, OSSystemExtensionRequestDelegate, Sendable {
    private let continuation: AsyncStream<SystemExtensionEvent>.Continuation

    init(continuation: AsyncStream<SystemExtensionEvent>.Continuation) {
        self.continuation = continuation
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        continuation.yield(.needsApproval)
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        continuation.yield(result == .completed ? .completed : .completesAfterReboot)
        continuation.finish()
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) {
        continuation.yield(.failed(reason: error.localizedDescription))
        continuation.finish()
    }
}
