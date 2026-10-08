import Domain
import TestSupport

/// `CameraSource` the test drives: `emit` delivers an `IncomingSurface`
/// straight to the subject (no executor hop — the fake stands in for the data
/// source that already did it).
public final class FakeCameraSource: CameraSource, Sendable {
    private struct State {
        var descriptor: SurfaceDescriptor?
        var onFrame: (@Sendable (IncomingSurface) -> Void)?
        var onEnd: (@Sendable (CaptureEnd) -> Void)?
        var startError: CaptureSessionError?
        var startCount = 0
        var stopCount = 0
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
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        try state.withLock { state in
            state.startCount += 1
            if let error = state.startError { throw error }
            state.descriptor = descriptor
            state.onFrame = onFrame
            state.onEnd = onEnd
        }
    }

    public func stop() {
        state.withLock { state in
            state.stopCount += 1
            state.onFrame = nil
            state.onEnd = nil
        }
    }

    public func emit(_ surface: IncomingSurface) {
        state.current.onFrame?(surface)
    }

    public func emit(_ handle: any SurfaceHandle, descriptor: SurfaceDescriptor = .hd720, at time: HostTimestamp) {
        emit(IncomingSurface(handle: handle, descriptor: descriptor, presentationTime: time))
    }

    public func end(_ reason: CaptureEnd) {
        state.current.onEnd?(reason)
    }
}

/// `CameraPermission` with a scripted decision for the one-time request.
public final class FakeCameraPermission: CameraPermission, Sendable {
    private let current: Locked<CameraAuthorizationStatus>
    private let decision: Locked<CameraAuthorizationStatus>
    public let requests = Collector<Void>()

    public init(status: CameraAuthorizationStatus, decision: CameraAuthorizationStatus = .authorized) {
        current = Locked(status)
        self.decision = Locked(decision)
    }

    public func status() -> CameraAuthorizationStatus { current.current }

    public func request() async -> CameraAuthorizationStatus {
        requests.append(())
        let decided = decision.current
        return current.withLock { status in
            guard status == .notDetermined else { return status }
            status = decided
            return status
        }
    }
}

/// `CameraRepository` the test drives with ready-made `FrameRef`s.
public final class FakeCameraRepository: CameraRepository, Sendable {
    private struct State {
        var authorization: CameraAuthorizationStatus
        var requestDecision: CameraAuthorizationStatus
        var descriptor: SurfaceDescriptor?
        var onFrame: (@Sendable (FrameRef) -> Void)?
        var onEnd: (@Sendable (CaptureEnd) -> Void)?
        var startError: CaptureSessionError?
        var startCount = 0
        var stopCount = 0
    }

    private let state: Locked<State>
    public let authorizationRequests = Collector<Void>()

    public init(authorization: CameraAuthorizationStatus = .authorized, requestDecision: CameraAuthorizationStatus = .authorized) {
        state = Locked(State(authorization: authorization, requestDecision: requestDecision))
    }

    public var isRunning: Bool { state.current.onFrame != nil }
    public var descriptor: SurfaceDescriptor? { state.current.descriptor }
    public var startCount: Int { state.current.startCount }
    public var stopCount: Int { state.current.stopCount }

    public func failStart(with error: CaptureSessionError?) {
        state.withLock { $0.startError = error }
    }

    public func authorizationStatus() -> CameraAuthorizationStatus { state.current.authorization }

    public func requestAuthorization() async -> CameraAuthorizationStatus {
        authorizationRequests.append(())
        return state.withLock { state in
            guard state.authorization == .notDetermined else { return state.authorization }
            state.authorization = state.requestDecision
            return state.authorization
        }
    }

    public func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (FrameRef) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        try state.withLock { state in
            state.startCount += 1
            if let error = state.startError { throw error }
            state.descriptor = descriptor
            state.onFrame = onFrame
            state.onEnd = onEnd
        }
    }

    public func stop() {
        state.withLock { state in
            state.stopCount += 1
            state.onFrame = nil
            state.onEnd = nil
        }
    }

    public func emit(_ frame: FrameRef) {
        state.current.onFrame?(frame)
    }

    public func end(_ reason: CaptureEnd) {
        state.current.onEnd?(reason)
    }
}
