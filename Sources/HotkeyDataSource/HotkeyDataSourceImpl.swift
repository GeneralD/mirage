import Dependencies
import Domain

/// The real `Hotkeys` (hackathon #177): registers the bindings through `HotkeyGateway`, keeps
/// what the OS accepted in `registration`, and hands each press of a registered hotkey to the
/// presses stream in place, as the `HotkeyAction` its id names.
///
/// **Registering.** A `register` releases the hotkeys of the call before it, makes sure the press
/// observer is installed (the first call that finds none installs it, and it is kept for the life
/// of the process), then asks the OS for each binding in order. A binding the OS refuses is released
/// at once, logged to `ErrorLog` and listed in `failed`. An observer the OS refuses leaves nothing
/// registered: every binding fails, and the next `register` asks for the observer again.
///
/// **Presses.** The id the OS reports is the `HotkeyAction`'s raw value, so an id that no action has
/// is dropped. The observer reads the stream in place at the moment of the press, so a second
/// `presses()` takes over from the first without a second observer.
///
/// Everything runs on the main actor, which is where Carbon calls back, so no lock is needed.
@MainActor
public final class HotkeyDataSourceImpl {
    @Dependency(\.hotkeyGateway) private var gateway
    @Dependency(\.errorLog) private var errorLog

    /// The press observer. Installed by the first `register` that finds none, and never released.
    private var observer: (any HotkeyHandle)?
    /// The hotkeys the last `register` armed and the OS accepted, released before the next one.
    private var handles: [any HotkeyHandle] = []
    /// The stream `presses()` returned last. A press goes to it and to no other stream.
    private var continuation: AsyncStream<HotkeyAction>.Continuation?

    public private(set) var registration: HotkeyRegistration = .empty

    public nonisolated init() {}
}

extension HotkeyDataSourceImpl: Hotkeys {
    public func presses() -> AsyncStream<HotkeyAction> {
        continuation?.finish()
        let (stream, next) = AsyncStream<HotkeyAction>.makeStream()
        continuation = next
        return stream
    }

    public func register(_ bindings: [HotkeyBinding]) -> HotkeyRegistration {
        releaseHotkeys()
        guard installObserverIfNeeded() else {
            registration = HotkeyRegistration(failed: bindings.map(\.action))
            return registration
        }
        let attempts = bindings.map { binding in
            Attempt(
                action: binding.action,
                handle: gateway.register(id: UInt32(binding.action.rawValue), keyCode: binding.keyCode, modifiers: binding.modifiers))
        }
        let accepted = attempts.filter { $0.handle.status == 0 }
        let refused = attempts.filter { $0.handle.status != 0 }
        for attempt in refused {
            attempt.handle.release()
            errorLog.record(.app, "hotkey \(attempt.action) not registered (status \(attempt.handle.status))")
        }
        handles = accepted.map(\.handle)
        registration = HotkeyRegistration(registered: accepted.map(\.action), failed: refused.map(\.action))
        return registration
    }

    public func unregisterAll() {
        releaseHotkeys()
    }
}

extension HotkeyDataSourceImpl {
    /// Gives back the hotkeys of the last `register` and forgets what they were.
    private func releaseHotkeys() {
        for handle in handles {
            handle.release()
        }
        handles = []
        registration = .empty
    }

    /// Hands a press the OS reported to the stream in place. An id that no action has is dropped.
    private func deliver(_ id: UInt32) {
        guard let action = HotkeyAction(rawValue: Int(id)) else { return }
        continuation?.yield(action)
    }

    /// Installs the press observer when there is none. `false` when the OS refused it: the status
    /// is logged, the refused handle is released, and nothing is kept, so the next `register` asks again.
    private func installObserverIfNeeded() -> Bool {
        if observer != nil { return true }
        let installed = gateway.observePresses { [weak self] id in
            MainActor.assumeIsolated {
                self?.deliver(id)
            }
        }
        guard installed.status == 0 else {
            installed.release()
            errorLog.record(.app, "hotkey press observer not installed (status \(installed.status))")
            return false
        }
        observer = installed
        return true
    }
}

/// One binding `register` asked the OS for, with the handle the OS answered with.
private struct Attempt {
    let action: HotkeyAction
    let handle: any HotkeyHandle
}
