import Domain
import TestSupport

/// The calls made to a camera use case, in the order they were made.
public enum CameraUseCaseCall: Sendable, Hashable {
    case refresh
}

/// `CameraSelectionUseCase` the test drives. `refresh()` answers the state set by `setState(_:)` and records
/// `.refresh` in `calls`. `changes()` makes a new stream on every call, buffered to one element as the live
/// stream is; `streamsOpened` counts the calls and `streamsClosed` the streams whose consumption ended.
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

    public init(state: CameraState = .empty) {
        self.state = Locked(State(cameraState: state))
    }

    /// Sets the state that the next `refresh()` returns.
    public func setState(_ cameraState: CameraState) {
        state.withLock { $0.cameraState = cameraState }
    }

    /// Yields one element on every stream that `changes()` has made and that has not ended.
    public func emitChange() {
        for continuation in state.current.changeStreams.values {
            continuation.yield(())
        }
    }

    public func refresh() -> CameraState {
        calls.append(.refresh)
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

    private func end(_ id: Int) {
        state.withLock { _ = $0.changeStreams.removeValue(forKey: id) }
        streamsClosed.append(())
    }
}
