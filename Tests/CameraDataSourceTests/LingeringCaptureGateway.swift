import Domain
import TestDoubles
import TestSupport

/// A capture gateway whose callbacks outlive the handle's `stop()` and a
/// replacing `start`, like samples already sitting on the capture queue when
/// the session is torn down. It records the callbacks even when `start` is
/// made to fail, because a real session can wire its delegate before the
/// failing step.
final class LingeringCaptureGateway: CaptureSessionGateway, Sendable {
    private struct Session {
        let onFrame: @Sendable (CapturedSurface) -> Void
        let onEnd: @Sendable (CaptureEnd) -> Void
    }

    private struct State {
        var sessions: [Session] = []
        var failNext = false
        var stopCount = 0
        var whileStarting: (@Sendable () -> Void)?
    }

    /// Stopping it only counts; the callbacks keep delivering.
    private struct Handle: CaptureSessionHandle {
        let gateway: LingeringCaptureGateway

        func stop() { gateway.state.withLock { $0.stopCount += 1 } }
    }

    private let state = Locked(State())

    var startCount: Int { state.current.sessions.count }
    var stopCount: Int { state.current.stopCount }

    func failNextStart() {
        state.withLock { $0.failNext = true }
    }

    /// Runs inside `start`, after the callbacks are wired and before the handle
    /// is returned: what another thread does while AVFoundation is still configuring.
    func whileStarting(_ action: @escaping @Sendable () -> Void) {
        state.withLock { $0.whileStarting = action }
    }

    func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws -> any CaptureSessionHandle {
        try state.withLock { state in
            state.sessions.append(Session(onFrame: onFrame, onEnd: onEnd))
            guard state.failNext else { return }
            state.failNext = false
            throw CaptureSessionError.deviceUnavailable
        }
        state.current.whileStarting?()
        return Handle(gateway: self)
    }

    /// A frame from the most recent session.
    func emit(_ handle: any SurfaceHandle, seconds: Double) {
        state.current.sessions.last?.onFrame(CapturedSurface(handle: handle, descriptor: .hd720, presentationSeconds: seconds))
    }

    /// A frame from the first session, even after later `start`s replaced it.
    func emitFirstSession(_ handle: any SurfaceHandle, seconds: Double) {
        state.current.sessions.first?.onFrame(CapturedSurface(handle: handle, descriptor: .hd720, presentationSeconds: seconds))
    }

    func endFirstSession(_ reason: CaptureEnd) {
        state.current.sessions.first?.onEnd(reason)
    }
}
