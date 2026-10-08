import Domain
import TestSupport

/// Extension-side receiver the test drives: `start` parks until `stop()` (or
/// until `failStart` is scripted); `emit` delivers frames and events to the
/// subject while parked.
public final class FakeFrameReceiver: FrameReceiver, Sendable {
    private struct State {
        var onFrame: (@Sendable (IncomingSurface) -> Void)?
        var onEvent: (@Sendable (ReceiverEvent) -> Void)?
        var startError: MachError?
        var stopSignal: CheckedContinuation<Void, Never>?
        var startCount = 0
        var stopCount = 0
    }

    private let state = Locked(State())
    public let started = Collector<Void>()

    public init() {}

    public var isRunning: Bool { state.current.onFrame != nil }
    public var startCount: Int { state.current.startCount }
    public var stopCount: Int { state.current.stopCount }

    public func failStart(with error: MachError?) {
        state.withLock { $0.startError = error }
    }

    public func start(
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) async throws {
        try state.withLock { state in
            state.startCount += 1
            if let error = state.startError { throw error }
            state.onFrame = onFrame
            state.onEvent = onEvent
        }
        started.append(())
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let alreadyStopped = state.withLock { state -> Bool in
                    guard state.onFrame != nil else { return true }
                    state.stopSignal = continuation
                    return false
                }
                if alreadyStopped { continuation.resume() }
            }
        } onCancel: {
            stop()
        }
    }

    public func stop() {
        let signal = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.stopCount += 1
            state.onFrame = nil
            state.onEvent = nil
            defer { state.stopSignal = nil }
            return state.stopSignal
        }
        signal?.resume()
    }

    public func emit(_ surface: IncomingSurface) {
        state.current.onFrame?(surface)
    }

    public func emit(_ handle: any SurfaceHandle, descriptor: SurfaceDescriptor = .hd720, at time: HostTimestamp) {
        emit(IncomingSurface(handle: handle, descriptor: descriptor, presentationTime: time))
    }

    public func emit(_ event: ReceiverEvent) {
        state.current.onEvent?(event)
    }
}

/// `FrameReceiverRepository` with the same driving surface, over `FrameRef`s.
public final class FakeFrameReceiverRepository: FrameReceiverRepository, Sendable {
    private struct State {
        var onFrame: (@Sendable (FrameRef) -> Void)?
        var onEvent: (@Sendable (ReceiverEvent) -> Void)?
        var startError: MachError?
        var stopSignal: CheckedContinuation<Void, Never>?
        var startCount = 0
        var stopCount = 0
    }

    private let state = Locked(State())
    public let started = Collector<Void>()

    public init() {}

    public var isRunning: Bool { state.current.onFrame != nil }
    public var startCount: Int { state.current.startCount }
    public var stopCount: Int { state.current.stopCount }

    public func failStart(with error: MachError?) {
        state.withLock { $0.startError = error }
    }

    public func start(
        onFrame: @escaping @Sendable (FrameRef) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) async throws {
        try state.withLock { state in
            state.startCount += 1
            if let error = state.startError { throw error }
            state.onFrame = onFrame
            state.onEvent = onEvent
        }
        started.append(())
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let alreadyStopped = state.withLock { state -> Bool in
                    guard state.onFrame != nil else { return true }
                    state.stopSignal = continuation
                    return false
                }
                if alreadyStopped { continuation.resume() }
            }
        } onCancel: {
            stop()
        }
    }

    public func stop() {
        let signal = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.stopCount += 1
            state.onFrame = nil
            state.onEvent = nil
            defer { state.stopSignal = nil }
            return state.stopSignal
        }
        signal?.resume()
    }

    public func emit(_ frame: FrameRef) {
        state.current.onFrame?(frame)
    }

    public func emit(_ event: ReceiverEvent) {
        state.current.onEvent?(event)
    }
}
