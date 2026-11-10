import Dependencies
import Domain

/// The host's preview attach and detach: a pass-through of the pipeline's preview
/// that turns each outcome into a log line, and each refusal into a `PreviewRefusal`.
public struct PreviewInteractorImpl: Sendable {
    @Dependency(\.framePipelineUseCase) private var pipeline
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension PreviewInteractorImpl: PreviewInteractor {
    @MainActor
    public func attach(_ target: any PreviewTargetHandle) -> PreviewAttachResult {
        do {
            try pipeline.attachPreview(target)
            developerLog.record(.preview, "preview pane attached")
            return .attached
        } catch {
            errorLog.record(.preview, "preview pane not attached: \(error)")
            return .refused(refusal(for: error))
        }
    }

    public func detach(_ target: any PreviewTargetHandle) {
        pipeline.detachPreview(target)
        developerLog.record(.preview, "preview pane detached")
    }
}

extension PreviewInteractorImpl {
    /// The one place an attach error becomes a refusal; an error no case names is `.unavailable`.
    private func refusal(for error: any Error) -> PreviewRefusal {
        switch error {
        case GPUError.noDevice:
            return .noDevice
        case PreviewError.foreignTarget:
            return .foreignTarget
        default:
            return .unavailable
        }
    }
}
