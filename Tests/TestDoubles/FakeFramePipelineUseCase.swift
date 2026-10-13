import Domain
import TestSupport

/// `FramePipelineUseCase` as the interactor suites see it: records what the
/// launch asked of the pipeline — starts (descriptor and rate), stops and the
/// views attached to its preview — and appends `"start"` to `order` so a launch
/// that shares the collector with other fakes can be checked for order.
/// `start` throws `failure` when given one; `attachPreview` throws `attachRefusal`
/// (recording nothing), like a sink that refuses a foreign target.
public final class FakeFramePipelineUseCase: FramePipelineUseCase, Sendable {
    private let failure: (any Error)?
    private let attachRefusal: PreviewError?
    public let starts = Collector<SurfaceDescriptor>()
    public let rates = Collector<FrameRate>()
    public let stops = Collector<Void>()
    /// The views handed to `attachPreview`, by identity.
    public let attached = Collector<ObjectIdentifier>()
    private let order: Collector<String>

    public init(failure: (any Error)? = nil, attachRefusal: PreviewError? = nil, order: Collector<String> = Collector()) {
        self.failure = failure
        self.attachRefusal = attachRefusal
        self.order = order
    }

    public var stats: PipelineStats { .empty }

    public func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        order.append("start")
        starts.append(descriptor)
        rates.append(frameRate)
        try failure.map { throw $0 }
    }

    public func stop() {
        stops.append(())
    }

    @MainActor
    public func attachPreview(_ target: any PreviewTargetHandle) throws {
        if let attachRefusal { throw attachRefusal }
        attached.append(ObjectIdentifier(target))
    }
}
