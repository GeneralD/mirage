import Domain
import TestSupport

/// Host-side transport the test controls: `connect` resolves per the scripted
/// outcome, `send` records or drops with the scripted reason, `emit` pushes a
/// transport event to the observer.
public final class FakeFrameTransport: FrameTransport, Sendable {
    private struct State {
        var connected = false
        var connectError: MachError?
        var dropReason: FrameDropReason?
        var onEvent: (@Sendable (FrameTransportEvent) -> Void)?
        var connectCount = 0
        var disconnectCount = 0
    }

    private let state = Locked(State())
    public let sent = Collector<(surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp)>()

    public init() {}

    public var isConnected: Bool { state.current.connected }
    public var connectCount: Int { state.current.connectCount }
    public var disconnectCount: Int { state.current.disconnectCount }

    public func failConnect(with error: MachError?) {
        state.withLock { $0.connectError = error }
    }

    public func dropSends(with reason: FrameDropReason?) {
        state.withLock { $0.dropReason = reason }
    }

    public func connect() async throws {
        try state.withLock { state in
            state.connectCount += 1
            if let error = state.connectError { throw error }
            state.connected = true
        }
        state.current.onEvent?(.connected)
    }

    public func disconnect() {
        state.withLock { state in
            state.disconnectCount += 1
            state.connected = false
        }
    }

    public func send(_ surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) -> SendOutcome {
        let outcome = state.withLock { state -> SendOutcome in
            guard state.connected else { return .dropped(.notConnected) }
            return state.dropReason.map(SendOutcome.dropped) ?? .sent
        }
        guard outcome.wasSent else { return outcome }
        sent.append((surface, descriptor, presentationTime))
        return outcome
    }

    public func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {
        state.withLock { $0.onEvent = onEvent }
    }

    public func emit(_ event: FrameTransportEvent) {
        state.current.onEvent?(event)
    }
}

/// `VirtualCameraSink` that records every `FrameRef` it was asked to send.
public final class FakeVirtualCameraSink: VirtualCameraSink, Sendable {
    private struct State {
        var connected = false
        var connectError: MachError?
        var dropReason: FrameDropReason?
        var onEvent: (@Sendable (FrameTransportEvent) -> Void)?
        var connectCount = 0
        var disconnectCount = 0
    }

    private let state = Locked(State())
    public let sent = Collector<FrameRef>()

    public init() {}

    public var isConnected: Bool { state.current.connected }
    public var connectCount: Int { state.current.connectCount }
    public var disconnectCount: Int { state.current.disconnectCount }

    public func failConnect(with error: MachError?) {
        state.withLock { $0.connectError = error }
    }

    public func dropSends(with reason: FrameDropReason?) {
        state.withLock { $0.dropReason = reason }
    }

    public func connect() async throws {
        try state.withLock { state in
            state.connectCount += 1
            if let error = state.connectError { throw error }
            state.connected = true
        }
        state.current.onEvent?(.connected)
    }

    public func disconnect() {
        state.withLock { state in
            state.disconnectCount += 1
            state.connected = false
        }
    }

    public func send(_ frame: FrameRef) -> SendOutcome {
        let outcome = state.withLock { state -> SendOutcome in
            guard state.connected else { return .dropped(.notConnected) }
            return state.dropReason.map(SendOutcome.dropped) ?? .sent
        }
        guard outcome.wasSent else { return outcome }
        sent.append(frame)
        return outcome
    }

    public func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {
        state.withLock { $0.onEvent = onEvent }
    }

    public func emit(_ event: FrameTransportEvent) {
        state.current.onEvent?(event)
    }
}
