import Domain
import TestSupport

/// `FramePipelineUseCase` as the interactor suites see it: records what the
/// launch asked of the pipeline — starts (descriptor and rate), stops, the bypass
/// values set and the views attached to its preview — and appends `"start"` to `order` so a launch
/// that shares the collector with other fakes can be checked for order.
/// `start` throws `failure` when given one; `attachPreview` throws `attachRefusal`
/// (recording nothing), like a sink that refuses a foreign target, and then `attachFailure`
/// (also recording nothing) for any other error the pipeline gives back.
/// `stats` reads what `script(stats:)` last set, `.empty` until then.
public final class FakeFramePipelineUseCase: FramePipelineUseCase, Sendable {
    private let failure: (any Error)?
    private let attachRefusal: PreviewError?
    private let attachFailure: (any Error)?
    private let scriptedStats = Locked(PipelineStats.empty)
    public let starts = Collector<SurfaceDescriptor>()
    public let rates = Collector<FrameRate>()
    public let stops = Collector<Void>()
    /// The values handed to `setBypass`, in call order.
    public let bypasses = Collector<Bool>()
    /// The views handed to `attachPreview`, by identity.
    public let attached = Collector<ObjectIdentifier>()
    /// The views handed to `detachPreview`, by identity.
    public let detached = Collector<ObjectIdentifier>()
    private let order: Collector<String>

    public init(
        failure: (any Error)? = nil,
        attachRefusal: PreviewError? = nil,
        order: Collector<String> = Collector(),
        attachFailure: (any Error)? = nil
    ) {
        self.failure = failure
        self.attachRefusal = attachRefusal
        self.attachFailure = attachFailure
        self.order = order
    }

    /// Makes `stats` report `stats` from now on.
    public func script(stats: PipelineStats) {
        scriptedStats.set(stats)
    }

    public var stats: PipelineStats { scriptedStats.current }

    public func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        order.append("start")
        starts.append(descriptor)
        rates.append(frameRate)
        try failure.map { throw $0 }
    }

    public func stop() {
        stops.append(())
    }

    public func setBypass(_ bypassed: Bool) {
        bypasses.append(bypassed)
    }

    @MainActor
    public func attachPreview(_ target: any PreviewTargetHandle) throws {
        if let attachRefusal { throw attachRefusal }
        if let attachFailure { throw attachFailure }
        attached.append(ObjectIdentifier(target))
    }

    public func detachPreview(_ target: any PreviewTargetHandle) {
        detached.append(ObjectIdentifier(target))
    }
}
