import Domain
import TestSupport

/// `SettingsRepository` holding the chosen effect and the disabled-effect records in memory:
/// `selectedEffect()` answers what was given at the start or last set, and `disabledEffects()`
/// what was given at the start or last set as well. `writes` records every `setSelectedEffect`,
/// in order, so a subject that must not persist is asserted to have written nothing;
/// `disabledWrites` records every `setDisabledEffects` array the same way, and `disabledReads`
/// every `disabledEffects()` call.
///
/// Both kinds of call answer at once unless the test asked to hold them (`holdReads()`,
/// `holdWrites()`, `holdDisabledWrites()`): then each one suspends until `complete(_:)`, in any
/// order, like a settings store that is slow to answer. That is how "something else happens
/// while the subject is reading or remembering the choice" is a sequence the test writes down.
/// A held read answers what was stored when it began; a held write has stored its value by
/// then (it is remembered, but the call has not returned yet).
///
/// The hotkeys flag and the schema version answer at once and are never held. `hotkeyFlagWrites`
/// records every `setHotkeysEnabled`, `stamps` every `stampSchemaVersion` version, and `resets` one
/// entry per `resetAll()`. `resetAll()` puts every value back to its default, as the live reset does.
/// The parameter values answer at once and are never held: `parameterReads` records every
/// `parameterValues(of:)` call, and `parameterWrites` records every `setParameterValues` call, which
/// replaces the values of its effect and leaves the other effects alone.
///
/// The system members answer at once as well (hackathon #183). The launch-at-login status starts at
/// `launchAtLogin` and moves the way `LoginItem` does: `setLaunchAtLogin` answers `on ? .on : .off`
/// and leaves `.unavailable` alone. `launchRequests` records every `setLaunchAtLogin` and
/// `settingsOpens` every `openLoginItemsSettings`. The hotkeys registration answers what
/// `script(registration:)` set, once, or else that every binding is registered; `registeredBindings`
/// records every `registerHotkeys` and `unregisters` every `unregisterHotkeys`, which leaves the
/// registration `.empty`. `hotkeyPresses()` opens the stream the next `pressHotkey(_:)` goes to, and
/// ends the one before it.
public final class FakeSettingsRepository: SettingsRepository, Sendable {
    /// One call that is parked until the test completes it.
    public struct Request: Sendable {
        public enum Call: Sendable, Equatable {
            case read
            case write(EffectID)
            case writeDisabled([DisabledEffectRecord])
        }

        public let id: Int
        public let call: Call
        /// The repository that issued it: ids restart at 1 per instance, so the id alone cannot tell a stranger's request.
        fileprivate let origin: ObjectIdentifier
    }

    /// One `setParameterValues` call: the effect, and the dictionary that replaced its values.
    public struct ParameterWrite: Sendable, Equatable {
        public let id: EffectID
        public let values: [String: EffectParameterValue]

        public init(id: EffectID, values: [String: EffectParameterValue]) {
            self.id = id
            self.values = values
        }
    }

    private struct State {
        var selected: EffectID?
        var disabled: [DisabledEffectRecord]
        var hotkeysEnabled: Bool
        var schemaVersion: StoredSchemaVersion
        var launchAtLogin: LaunchAtLoginStatus
        var parameters: [EffectID: [String: EffectParameterValue]]
        var scripted: HotkeyRegistration?
        var hotkeyRegistration: HotkeyRegistration = .empty
        var pressContinuation: AsyncStream<HotkeyAction>.Continuation?
        var holdingReads = false
        var holdingWrites = false
        var holdingDisabledWrites = false
        var nextRequest = 1
        var parked: [Int: CheckedContinuation<Void, Never>] = [:]
    }

    private let state: Locked<State>
    /// One entry per `selectedEffect()` call.
    public let reads = Collector<Void>()
    /// The ids `setSelectedEffect` was called with, in call order.
    public let writes = Collector<EffectID>()
    /// One entry per `disabledEffects()` call.
    public let disabledReads = Collector<Void>()
    /// The arrays `setDisabledEffects` was called with, in call order.
    public let disabledWrites = Collector<[DisabledEffectRecord]>()
    /// The calls that were parked (`holdReads()`, `holdWrites()`, `holdDisabledWrites()`), in call order. A request is recorded
    /// in the same step that parks it, so a test that sees one can always complete it.
    public let heldRequests = Collector<Request>()
    /// The values `setHotkeysEnabled` was called with, in call order.
    public let hotkeyFlagWrites = Collector<Bool>()
    /// The versions `stampSchemaVersion` was called with, in call order.
    public let stamps = Collector<Int>()
    /// One entry per `resetAll()` call, in call order.
    public let resets = Collector<Void>()
    /// The values `setLaunchAtLogin` was called with, in call order, including a call that changed nothing.
    public let launchRequests = Collector<Bool>()
    /// One entry per `openLoginItemsSettings()` call, in call order.
    public let settingsOpens = Collector<Void>()
    /// The bindings `registerHotkeys` was called with, in call order.
    public let registeredBindings = Collector<[HotkeyBinding]>()
    /// One entry per `unregisterHotkeys()` call, in call order.
    public let unregisters = Collector<Void>()
    /// One entry per `parameterValues(of:)` call, in call order.
    public let parameterReads = Collector<EffectID>()
    /// The `setParameterValues` calls, in call order.
    public let parameterWrites = Collector<ParameterWrite>()

    public init(
        selected: EffectID? = nil,
        disabled: [DisabledEffectRecord] = [],
        hotkeysEnabled: Bool = true,
        schemaVersion: StoredSchemaVersion = .missing,
        launchAtLogin: LaunchAtLoginStatus = .off,
        parameters: [EffectID: [String: EffectParameterValue]] = [:]
    ) {
        state = Locked(
            State(
                selected: selected,
                disabled: disabled,
                hotkeysEnabled: hotkeysEnabled,
                schemaVersion: schemaVersion,
                launchAtLogin: launchAtLogin,
                parameters: parameters
            ))
    }

    /// Calls that are parked right now.
    public var pendingCount: Int { state.current.parked.count }

    /// From now on every `selectedEffect()` suspends until `complete(_:)`; `holdReads(false)` goes back to
    /// answering at once (calls already parked stay parked).
    public func holdReads(_ holding: Bool = true) {
        state.withLock { $0.holdingReads = holding }
    }

    /// From now on every `setSelectedEffect` suspends, after storing, until `complete(_:)`;
    /// `holdWrites(false)` goes back to returning at once (calls already parked stay parked).
    public func holdWrites(_ holding: Bool = true) {
        state.withLock { $0.holdingWrites = holding }
    }

    /// From now on every `setDisabledEffects` suspends, after storing, until `complete(_:)`;
    /// `holdDisabledWrites(false)` goes back to returning at once (calls already parked stay parked).
    public func holdDisabledWrites(_ holding: Bool = true) {
        state.withLock { $0.holdingDisabledWrites = holding }
    }

    /// Resumes the parked call; `false` when it is unknown, came from another repository, or is already resumed.
    @discardableResult
    public func complete(_ request: Request) -> Bool {
        guard request.origin == ObjectIdentifier(self) else { return false }
        guard let continuation = state.withLock({ $0.parked.removeValue(forKey: request.id) }) else { return false }
        continuation.resume()
        return true
    }

    /// Makes the next `registerHotkeys` answer `registration`, and sets `hotkeyRegistration` to it. The script is
    /// used once: the `registerHotkeys` after it answers that every binding is registered.
    public func script(registration: HotkeyRegistration) {
        state.withLock { $0.scripted = registration }
    }

    /// Delivers `action` to the stream `hotkeyPresses()` returned last. Nothing happens when no stream is open.
    public func pressHotkey(_ action: HotkeyAction) {
        state.withLock { $0.pressContinuation }?.yield(action)
    }

    public func selectedEffect() async -> EffectID? {
        reads.append(())
        let answer = state.current.selected
        await parkIfHeld(.read)
        return answer
    }

    public func setSelectedEffect(_ id: EffectID) async {
        state.withLock { $0.selected = id }
        writes.append(id)
        await parkIfHeld(.write(id))
    }

    public func disabledEffects() async -> [DisabledEffectRecord] {
        disabledReads.append(())
        return state.current.disabled
    }

    public func setDisabledEffects(_ records: [DisabledEffectRecord]) async {
        state.withLock { $0.disabled = records }
        disabledWrites.append(records)
        await parkIfHeld(.writeDisabled(records))
    }

    public func hotkeysEnabled() async -> Bool {
        state.current.hotkeysEnabled
    }

    public func setHotkeysEnabled(_ on: Bool) async {
        state.withLock { $0.hotkeysEnabled = on }
        hotkeyFlagWrites.append(on)
    }

    public func parameterValues(of id: EffectID) async -> [String: EffectParameterValue] {
        parameterReads.append(id)
        return state.current.parameters[id] ?? [:]
    }

    public func setParameterValues(_ values: [String: EffectParameterValue], of id: EffectID) async {
        state.withLock { $0.parameters[id] = values }
        parameterWrites.append(ParameterWrite(id: id, values: values))
    }

    public func storedSchemaVersion() async -> StoredSchemaVersion {
        state.current.schemaVersion
    }

    public func stampSchemaVersion(_ version: Int) async {
        state.withLock { $0.schemaVersion = .version(version) }
        stamps.append(version)
    }

    /// Clears everything the live reset removes: the selection, the disabled records, the flag, the version
    /// and the parameter values of every effect (the live reset calls `removeAll()` on the key-value store).
    public func resetAll() async {
        state.withLock {
            $0.selected = nil
            $0.disabled = []
            $0.hotkeysEnabled = true
            $0.schemaVersion = .missing
            $0.parameters = [:]
        }
        resets.append(())
    }

    public var launchAtLoginStatus: LaunchAtLoginStatus {
        state.current.launchAtLogin
    }

    public func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus {
        launchRequests.append(on)
        return state.withLock { current in
            guard current.launchAtLogin != .unavailable else { return current.launchAtLogin }
            current.launchAtLogin = on ? .on : .off
            return current.launchAtLogin
        }
    }

    public func openLoginItemsSettings() {
        settingsOpens.append(())
    }

    public func registerHotkeys(_ bindings: [HotkeyBinding]) async -> HotkeyRegistration {
        registeredBindings.append(bindings)
        return state.withLock { state in
            let answer = state.scripted ?? HotkeyRegistration(registered: bindings.map(\.action))
            state.scripted = nil
            state.hotkeyRegistration = answer
            return answer
        }
    }

    public func unregisterHotkeys() async {
        state.withLock { $0.hotkeyRegistration = .empty }
        unregisters.append(())
    }

    public var hotkeyRegistration: HotkeyRegistration {
        get async { state.current.hotkeyRegistration }
    }

    public func hotkeyPresses() async -> AsyncStream<HotkeyAction> {
        let (stream, next) = AsyncStream<HotkeyAction>.makeStream()
        state.withLock { state in
            state.pressContinuation?.finish()
            state.pressContinuation = next
        }
        return stream
    }

    private func parkIfHeld(_ call: Request.Call) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.withLock { state in
                let holding: Bool
                switch call {
                case .read: holding = state.holdingReads
                case .write: holding = state.holdingWrites
                case .writeDisabled: holding = state.holdingDisabledWrites
                }
                guard holding else { return continuation.resume() }
                let id = state.nextRequest
                state.nextRequest += 1
                state.parked[id] = continuation
                heldRequests.append(Request(id: id, call: call, origin: ObjectIdentifier(self)))
            }
        }
    }
}
