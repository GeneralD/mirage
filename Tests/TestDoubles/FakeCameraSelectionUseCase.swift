import Domain
import TestSupport

/// The calls made to a camera use case, in the order they were made.
public enum CameraUseCaseCall: Sendable, Hashable {
    case refresh
    case selectDevice(String)
    case selectResolution(CameraResolution)
    case selectFrameRate(Int)
    case setMirrored(Bool)
}

/// `CameraSelectionUseCase` the test drives. `refresh()` and each command record their call in `calls`, and
/// answer the state set by `setState(_:)`. `changes()` makes a new stream on every call, buffered to one element
/// as the live stream is; `streamsOpened` counts the calls and `streamsClosed` the streams whose consumption ended.
/// `emitChange()` yields one element on every stream that has not ended yet.
public final class FakeCameraSelectionUseCase: CameraSelectionUseCase, Sendable {
    private struct State {
        var cameraState: CameraState
        var changeStreams: [Int: AsyncStream<Void>.Continuation] = [:]
        var nextStream = 0
    }

    private let state: Locked<State>
    /// One entry per use case call, in call order.
    public let calls = Collector<CameraUseCaseCall>()
    /// One entry per `changes()` call.
    public let streamsOpened = Collector<Void>()
    /// One entry per `changes()` stream whose consumption ended.
    public let streamsClosed = Collector<Void>()
    /// The body the next `refresh()` runs once: after its call is recorded, before its state is returned.
    private let hook = Locked<(@Sendable () -> Void)?>(nil)

    public init(state: CameraState = .empty) {
        self.state = Locked(State(cameraState: state))
    }

    /// Sets the state that the next `refresh()` or command returns.
    public func setState(_ cameraState: CameraState) {
        state.withLock { $0.cameraState = cameraState }
    }

    /// Makes `body` run once, inside the next `refresh()`, and then lets go of it.
    public func whileRefreshing(_ body: @escaping @Sendable () -> Void) {
        hook.set(body)
    }

    /// Yields one element on every stream that `changes()` has made and that has not ended.
    public func emitChange() {
        for continuation in state.current.changeStreams.values {
            continuation.yield(())
        }
    }

    public func refresh() -> CameraState {
        calls.append(.refresh)
        // Taken out under the lock and run outside it, so the body may call back into this double.
        let pending = hook.withLock { value -> (@Sendable () -> Void)? in
            let taken = value
            value = nil
            return taken
        }
        pending?()
        return state.current.cameraState
    }

    public func changes() -> AsyncStream<Void> {
        streamsOpened.append(())
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = state.withLock { locked -> Int in
            let id = locked.nextStream
            locked.nextStream += 1
            locked.changeStreams[id] = continuation
            return id
        }
        continuation.onTermination = { [weak self] _ in self?.end(id) }
        return stream
    }

    public func selectDevice(_ id: String) -> CameraState {
        calls.append(.selectDevice(id))
        return state.current.cameraState
    }

    public func selectResolution(_ resolution: CameraResolution) -> CameraState {
        calls.append(.selectResolution(resolution))
        return state.current.cameraState
    }

    public func selectFrameRate(_ framesPerSecond: Int) -> CameraState {
        calls.append(.selectFrameRate(framesPerSecond))
        return state.current.cameraState
    }

    public func setMirrored(_ isMirrored: Bool) -> CameraState {
        calls.append(.setMirrored(isMirrored))
        return state.current.cameraState
    }

    private func end(_ id: Int) {
        state.withLock { _ = $0.changeStreams.removeValue(forKey: id) }
        streamsClosed.append(())
    }
}
