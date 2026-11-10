import Domain
import TestSupport

/// `LoginItemGateway` that registers no login item. `status` is a raw `SMAppService.Status` value that
/// `register` and `unregister` move the way the system does, so a second `register` fails with
/// `alreadyRegistered`, and a second `unregister` with `notRegistered`. `failNext` makes the next call
/// to either fail once, and leaves the status as it was.
///
/// The fake's failures are its own vocabulary: the live gateway passes the system's errors through
/// unmapped, so nothing here is a mapping of them.
///
/// `registers`, `unregisters` and `settingsOpens` record every call in order, including a call that
/// throws, so a subject that must not call the gateway is asserted to have made no entry.
public final class FakeLoginItemGateway: LoginItemGateway, Sendable {
    /// The errors `register` and `unregister` throw.
    public enum Failure: Error, Sendable, Hashable {
        case alreadyRegistered
        case notRegistered
    }

    private struct State {
        var status: Int
        var pendingFailure: Failure?
    }

    private let state: Locked<State>
    /// One entry per `register` call, in call order.
    public let registers = Collector<Void>()
    /// One entry per `unregister` call, in call order.
    public let unregisters = Collector<Void>()
    /// One entry per `openSystemSettings` call, in call order.
    public let settingsOpens = Collector<Void>()

    public init(status: Int = 0) {
        state = Locked(State(status: status, pendingFailure: nil))
    }

    public func rawStatus() -> Int {
        state.current.status
    }

    public func register() throws {
        registers.append(())
        try state.withLock { state in
            if let failure = state.pendingFailure {
                state.pendingFailure = nil
                throw failure
            }
            if state.status == 1 { throw Failure.alreadyRegistered }
            state.status = 1
        }
    }

    public func unregister() throws {
        unregisters.append(())
        try state.withLock { state in
            if let failure = state.pendingFailure {
                state.pendingFailure = nil
                throw failure
            }
            if state.status == 0 || state.status == 3 { throw Failure.notRegistered }
            state.status = 0
        }
    }

    public func openSystemSettings() {
        settingsOpens.append(())
    }

    /// The next `register` or `unregister` throws `failure` once; the status does not change.
    public func failNext(_ failure: Failure) {
        state.withLock { $0.pendingFailure = failure }
    }

    /// Sets the raw status directly, as when the user approves or removes the item in System Settings.
    public func set(status: Int) {
        state.withLock { $0.status = status }
    }
}
