import Domain
import TestSupport

/// The CMIO stream as the test sees it: records the declared format and every
/// sent surface; `emit` relays a client start/stop to the subject.
public final class FakeStreamOutputGateway: StreamOutputGateway, Sendable {
    public struct Started: Sendable {
        public let deviceName: String
        public let descriptor: SurfaceDescriptor
        public let frameRate: FrameRate
    }

    private struct State {
        var started: Started?
        var onEvent: (@Sendable (StreamOutputEvent) -> Void)?
        var startError: StreamOutputError?
        var sendError: StreamOutputError?
    }

    private let state = Locked(State())
    public let sent = Collector<(surface: any SurfaceHandle, presentationTime: HostTimestamp)>()

    public init() {}

    public var started: Started? { state.current.started }

    public func failStart(with error: StreamOutputError?) {
        state.withLock { $0.startError = error }
    }

    public func failSend(with error: StreamOutputError?) {
        state.withLock { $0.sendError = error }
    }

    public func start(
        deviceName: String,
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        try state.withLock { state in
            if let error = state.startError { throw error }
            state.started = Started(deviceName: deviceName, descriptor: descriptor, frameRate: frameRate)
            state.onEvent = onEvent
        }
    }

    public func send(_ surface: any SurfaceHandle, presentationTime: HostTimestamp) throws {
        try state.withLock { state in
            if let error = state.sendError { throw error }
        }
        sent.append((surface, presentationTime))
    }

    public func emit(_ event: StreamOutputEvent) {
        state.current.onEvent?(event)
    }
}
