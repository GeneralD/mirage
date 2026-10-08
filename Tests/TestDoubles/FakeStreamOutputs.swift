import Domain
import TestSupport

/// `StreamOutput` the test controls: `setStreaming` flips the client state
/// (and relays the event), `send` records while streaming and drops otherwise.
public final class FakeStreamOutput: StreamOutput, Sendable {
    private struct State {
        var descriptor: SurfaceDescriptor?
        var frameRate: FrameRate?
        var streaming = false
        var startError: StreamOutputError?
        var onEvent: (@Sendable (StreamOutputEvent) -> Void)?
    }

    private let state = Locked(State())
    public let sent = Collector<(surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp)>()

    public init() {}

    public var descriptor: SurfaceDescriptor? { state.current.descriptor }
    public var frameRate: FrameRate? { state.current.frameRate }
    public var isStreaming: Bool { state.current.streaming }

    public func failStart(with error: StreamOutputError?) {
        state.withLock { $0.startError = error }
    }

    public func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        try state.withLock { state in
            if let error = state.startError { throw error }
            state.descriptor = descriptor
            state.frameRate = frameRate
            state.onEvent = onEvent
        }
    }

    public func send(_ surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) -> SendOutcome {
        guard state.current.streaming else { return .dropped(.noClient) }
        sent.append((surface, descriptor, presentationTime))
        return .sent
    }

    public func setStreaming(_ streaming: Bool) {
        let onEvent = state.withLock { state -> (@Sendable (StreamOutputEvent) -> Void)? in
            state.streaming = streaming
            return state.onEvent
        }
        onEvent?(streaming ? .streamStarted : .streamStopped)
    }
}

/// `StreamOutputRepository` with the same driving surface, over `FrameRef`s.
public final class FakeStreamOutputRepository: StreamOutputRepository, Sendable {
    private struct State {
        var descriptor: SurfaceDescriptor?
        var frameRate: FrameRate?
        var streaming = false
        var startError: StreamOutputError?
        var dropReason: FrameDropReason?
        var onEvent: (@Sendable (StreamOutputEvent) -> Void)?
    }

    private let state = Locked(State())
    public let sent = Collector<FrameRef>()

    public init() {}

    public var descriptor: SurfaceDescriptor? { state.current.descriptor }
    public var frameRate: FrameRate? { state.current.frameRate }
    public var isStreaming: Bool { state.current.streaming }

    public func failStart(with error: StreamOutputError?) {
        state.withLock { $0.startError = error }
    }

    public func dropSends(with reason: FrameDropReason?) {
        state.withLock { $0.dropReason = reason }
    }

    public func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        try state.withLock { state in
            if let error = state.startError { throw error }
            state.descriptor = descriptor
            state.frameRate = frameRate
            state.onEvent = onEvent
        }
    }

    public func send(_ frame: FrameRef) -> SendOutcome {
        let outcome = state.withLock { state -> SendOutcome in
            guard state.streaming else { return .dropped(.noClient) }
            return state.dropReason.map(SendOutcome.dropped) ?? .sent
        }
        guard outcome.wasSent else { return outcome }
        sent.append(frame)
        return outcome
    }

    public func setStreaming(_ streaming: Bool) {
        let onEvent = state.withLock { state -> (@Sendable (StreamOutputEvent) -> Void)? in
            state.streaming = streaming
            return state.onEvent
        }
        onEvent?(streaming ? .streamStarted : .streamStopped)
    }
}
