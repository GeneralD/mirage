import Domain
import TestDoubles
import TestSupport

/// A capture gateway whose callbacks outlive `stop()` and a replacing `start`,
/// like samples already sitting on the capture queue when the session is torn
/// down. It records the callbacks even when `start` is made to fail, because a
/// real session can wire its delegate before the failing step.
final class LingeringCaptureGateway: CaptureSessionGateway, Sendable {
    private struct Session {
        let onFrame: @Sendable (CapturedSurface) -> Void
        let onEnd: @Sendable (CaptureEnd) -> Void
    }

    private struct State {
        var sessions: [Session] = []
        var failNext = false
    }

    private let state = Locked(State())

    var startCount: Int { state.current.sessions.count }

    func failNextStart() {
        state.withLock { $0.failNext = true }
    }

    func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        try state.withLock { state in
            state.sessions.append(Session(onFrame: onFrame, onEnd: onEnd))
            guard state.failNext else { return }
            state.failNext = false
            throw CaptureSessionError.deviceUnavailable
        }
    }

    func stop() {}

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
