import Domain
import TestSupport

/// The camera the test drives: `emit` delivers a frame to the subject's
/// callback, `end` finishes the session. Set `startError` to make `start` throw.
/// Stopping the handle `start` returned clears the callbacks like a real
/// teardown does, so a frame emitted afterwards goes nowhere.
public final class FakeCaptureSessionGateway: CaptureSessionGateway, Sendable {
    private struct State {
        var descriptor: SurfaceDescriptor?
        var onFrame: (@Sendable (CapturedSurface) -> Void)?
        var onEnd: (@Sendable (CaptureEnd) -> Void)?
        var startError: CaptureSessionError?
        var startCount = 0
        var stopCount = 0
    }

    private struct Handle: CaptureSessionHandle {
        let gateway: FakeCaptureSessionGateway

        func stop() { gateway.stopSession() }
    }

    private let state = Locked(State())

    public init() {}

    public var isRunning: Bool { state.current.onFrame != nil }
    public var descriptor: SurfaceDescriptor? { state.current.descriptor }
    public var startCount: Int { state.current.startCount }
    public var stopCount: Int { state.current.stopCount }

    public func failStart(with error: CaptureSessionError?) {
        state.withLock { $0.startError = error }
    }

    public func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws -> any CaptureSessionHandle {
        try state.withLock { state in
            state.startCount += 1
            if let error = state.startError { throw error }
            state.descriptor = descriptor
            state.onFrame = onFrame
            state.onEnd = onEnd
        }
        return Handle(gateway: self)
    }

    private func stopSession() {
        state.withLock { state in
            state.stopCount += 1
            state.onFrame = nil
            state.onEnd = nil
        }
    }

    /// Delivers one frame as the capture queue would; a no-op when stopped.
    public func emit(_ surface: CapturedSurface) {
        state.current.onFrame?(surface)
    }

    public func emit(_ handle: any SurfaceHandle, descriptor: SurfaceDescriptor = .hd720, seconds: Double) {
        emit(CapturedSurface(handle: handle, descriptor: descriptor, presentationSeconds: seconds))
    }

    public func end(_ reason: CaptureEnd) {
        state.current.onEnd?(reason)
    }
}

/// Camera permission with a scripted answer to the system prompt.
public final class ScriptedCameraAuthorization: CameraAuthorizationGateway, Sendable {
    private let current: Locked<CameraAuthorizationStatus>
    private let answer: Locked<Bool>
    public let requests = Collector<Void>()

    public init(status: CameraAuthorizationStatus, grantsOnRequest: Bool = true) {
        current = Locked(status)
        answer = Locked(grantsOnRequest)
    }

    public func status() -> CameraAuthorizationStatus { current.current }

    public func requestAccess() async -> Bool {
        requests.append(())
        let granted = answer.current
        current.withLock { status in
            guard status == .notDetermined else { return }
            status = granted ? .authorized : .denied
        }
        return current.current.isGranted
    }
}
