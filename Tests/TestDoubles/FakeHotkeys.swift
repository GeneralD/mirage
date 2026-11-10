import Domain
import TestSupport

/// `Hotkeys` the test drives by hand. `register` records the bindings and answers what `script(_:)`
/// set, once, or else that every binding is registered. `presses()` opens the stream the next
/// `press(_:)` goes to, and ends the one before it. Nothing happens on its own.
///
/// `registration` is set before the call is recorded, and a stream is stored before `presses()`
/// returns, so a `press` made right after the call is not lost.
public final class FakeHotkeys: Hotkeys, @unchecked Sendable {
    private struct State {
        var continuation: AsyncStream<HotkeyAction>.Continuation?
        var scripted: HotkeyRegistration?
        var registration: HotkeyRegistration = .empty
    }

    private let state = Locked(State())
    /// Every `register` call, in order: the bindings it was given.
    public let registrations = Collector<[HotkeyBinding]>()
    /// Every `unregisterAll` call.
    public let unregisters = Collector<Void>()
    /// Every `presses()` call.
    public let streamRequests = Collector<Void>()

    public init() {}

    /// Makes the next `register` answer `registration`, and sets `registration` to it. The script is
    /// used once: the `register` after it answers that every binding is registered.
    public func script(_ registration: HotkeyRegistration) {
        state.withLock { $0.scripted = registration }
    }

    /// Delivers `action` to the stream `presses()` returned last. Nothing happens when no stream is open.
    public func press(_ action: HotkeyAction) {
        state.withLock { $0.continuation }?.yield(action)
    }

    @MainActor
    public var registration: HotkeyRegistration {
        state.withLock { $0.registration }
    }

    @MainActor
    public func presses() -> AsyncStream<HotkeyAction> {
        streamRequests.append(())
        let (stream, next) = AsyncStream<HotkeyAction>.makeStream()
        state.withLock { state in
            state.continuation?.finish()
            state.continuation = next
        }
        return stream
    }

    @MainActor
    public func register(_ bindings: [HotkeyBinding]) -> HotkeyRegistration {
        let answer = state.withLock { state -> HotkeyRegistration in
            let answer = state.scripted ?? HotkeyRegistration(registered: bindings.map(\.action))
            state.scripted = nil
            state.registration = answer
            return answer
        }
        registrations.append(bindings)
        return answer
    }

    @MainActor
    public func unregisterAll() {
        state.withLock { $0.registration = .empty }
        unregisters.append(())
    }
}
