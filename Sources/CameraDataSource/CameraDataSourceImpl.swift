import Dependencies
import Domain

/// Puts the capture session's frames on the host-time axis and the frame
/// executor. Every gateway callback arrives on the capture queue; hopping onto
/// the executor here makes everything above this class a single-threaded state
/// machine. A frame whose PTS does not advance past the previous one is dropped,
/// so downstream stages can rely on strictly increasing presentation times.
///
/// Each `start` mints a `Session`; the executor only accepts frames of the
/// current one, so samples queued before a `stop` (or a restart) never surface
/// afterwards and never occupy a pool slot.
public final class CameraDataSourceImpl: @unchecked Sendable {
    /// Identity token for one capture session; compared by reference.
    private final class Session: Sendable {}

    @Dependency(\.captureSessionGateway) private var captureSessionGateway
    @Dependency(\.frameExecutor) private var frameExecutor
    @Dependency(\.developerLog) private var developerLog

    // Executor-confined: every mutation runs on FrameExecutor.
    private var current: Session?
    // Executor-confined: every mutation runs on FrameExecutor.
    private var lastPresentation: HostTimestamp?

    public init() {}
}

extension CameraDataSourceImpl: CameraSource {
    /// M0 captures 1280x720 BGRA only; the gateway pins the same preset, so any
    /// other request is refused here instead of being half-honoured below.
    public func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        guard descriptor.matchesGeometry(of: .hd720) else {
            throw CaptureSessionError.configurationFailed("unsupported descriptor \(descriptor.width)x\(descriptor.height)")
        }
        let session = Session()
        // Queued before the gateway starts, so it runs ahead of the session's first frame.
        frameExecutor.run { [self] in begin(session) }
        do {
            try captureSessionGateway.start(
                descriptor: descriptor,
                onFrame: { [self] captured in frameExecutor.run { self.deliver(captured, from: session, to: onFrame) } },
                onEnd: { [self] reason in frameExecutor.run { self.finish(reason, from: session, to: onEnd) } }
            )
        } catch {
            frameExecutor.run { [self] in close(session) }
            throw error
        }
    }

    /// Stops the gateway at once, then retires the session on the executor: frames
    /// queued before this call still arrive in order, anything later is dropped.
    public func stop() {
        captureSessionGateway.stop()
        frameExecutor.run { [self] in close(current) }
    }
}

extension CameraDataSourceImpl {
    /// Runs on the executor. A new session starts from a clean monotonic floor.
    private func begin(_ session: Session) {
        current = session
        lastPresentation = nil
    }

    /// Runs on the executor. Retires `session` (or whatever is current when `nil`).
    private func close(_ session: Session?) {
        guard session === current else { return }
        current = nil
        lastPresentation = nil
    }

    /// Runs on the executor. The end of a session starts the next one from a clean floor.
    private func finish(_ reason: CaptureEnd, from session: Session, to onEnd: @Sendable (CaptureEnd) -> Void) {
        guard session === current else { return }
        lastPresentation = nil
        onEnd(reason)
    }

    /// Runs on the executor. Accepts the frame only when its PTS is newer than the last accepted one.
    private func deliver(_ captured: CapturedSurface, from session: Session, to onFrame: @Sendable (IncomingSurface) -> Void) {
        guard session === current else { return }
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
