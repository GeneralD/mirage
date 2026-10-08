import Dependencies
import Domain

/// Puts the capture session's frames on the host-time axis and the frame
/// executor. Every gateway callback arrives on the capture queue; hopping onto
/// the executor here makes everything above this class a single-threaded state
/// machine. A frame whose PTS does not advance past the previous one is dropped,
/// so downstream stages can rely on strictly increasing presentation times.
public final class CameraDataSourceImpl: @unchecked Sendable {
    @Dependency(\.captureSessionGateway) private var captureSessionGateway
    @Dependency(\.frameExecutor) private var frameExecutor
    @Dependency(\.developerLog) private var developerLog

    // Executor-confined: every mutation runs on FrameExecutor.
    private var lastPresentation: HostTimestamp?

    public init() {}
}

extension CameraDataSourceImpl: CameraSource {
    public func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        try captureSessionGateway.start(
            descriptor: descriptor,
            onFrame: { [self] captured in frameExecutor.run { self.deliver(captured, to: onFrame) } },
            onEnd: { [self] reason in frameExecutor.run { self.finish(reason, to: onEnd) } }
        )
    }

    public func stop() {
        captureSessionGateway.stop()
    }
}

extension CameraDataSourceImpl {
    /// Runs on the executor. A new session starts from a clean monotonic floor.
    private func finish(_ reason: CaptureEnd, to onEnd: @Sendable (CaptureEnd) -> Void) {
        lastPresentation = nil
        onEnd(reason)
    }

    /// Runs on the executor. Accepts the frame only when its PTS is newer than the last accepted one.
    private func deliver(_ captured: CapturedSurface, to onFrame: @Sendable (IncomingSurface) -> Void) {
        let time = HostTimestamp.seconds(captured.presentationSeconds)
        let incoming = IncomingSurface(handle: captured.handle, descriptor: captured.descriptor, presentationTime: time)
        guard let floor = lastPresentation else { return accept(incoming, to: onFrame) }
        guard time > floor else {
            developerLog.record(.camera, "dropped non-monotonic frame: pts \(time.nanoseconds)ns after \(floor.nanoseconds)ns")
            return
        }
        accept(incoming, to: onFrame)
    }

    private func accept(_ incoming: IncomingSurface, to onFrame: @Sendable (IncomingSurface) -> Void) {
        lastPresentation = incoming.presentationTime
        onFrame(incoming)
    }
}
