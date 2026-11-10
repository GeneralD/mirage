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

    private struct State {
        var selected: EffectID?
        var disabled: [DisabledEffectRecord]
        var hotkeysEnabled: Bool
        var schemaVersion: StoredSchemaVersion
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

    public init(
        selected: EffectID? = nil,
        disabled: [DisabledEffectRecord] = [],
        hotkeysEnabled: Bool = true,
        schemaVersion: StoredSchemaVersion = .missing
    ) {
        state = Locked(State(selected: selected, disabled: disabled, hotkeysEnabled: hotkeysEnabled, schemaVersion: schemaVersion))
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

    public func storedSchemaVersion() async -> StoredSchemaVersion {
        state.current.schemaVersion
    }

    public func stampSchemaVersion(_ version: Int) async {
        state.withLock { $0.schemaVersion = .version(version) }
        stamps.append(version)
    }

    /// Clears everything the live reset removes: the selection, the disabled records, the flag and the version.
    public func resetAll() async {
        state.withLock {
            $0.selected = nil
            $0.disabled = []
            $0.hotkeysEnabled = true
            $0.schemaVersion = .missing
        }
        resets.append(())
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
