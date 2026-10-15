import Domain
import TestSupport

/// `SettingsRepository` holding the chosen effect in memory: `selectedEffect()` answers
/// what was given at the start or last set, and `writes` records every
/// `setSelectedEffect`, in order, so a subject that must not persist is asserted to
/// have written nothing.
///
/// Both calls answer at once unless the test asked to hold them (`holdReads()`,
/// `holdWrites()`): then each one suspends until `complete(_:)`, in any order, like a
/// settings store that is slow to answer. That is how "something else happens while the
/// subject is reading or remembering the choice" is a sequence the test writes down. A
/// held read answers what was stored when it began; a held write has stored its value
/// by then (it is remembered, but the call has not returned yet).
public final class FakeSettingsRepository: SettingsRepository, Sendable {
    /// One call that is parked until the test completes it.
    public struct Request: Sendable {
        public enum Call: Sendable, Equatable {
            case read
            case write(EffectID)
        }

        public let id: Int
        public let call: Call
        /// The repository that issued it: ids restart at 1 per instance, so the id alone cannot tell a stranger's request.
        fileprivate let origin: ObjectIdentifier
    }

    private struct State {
        var selected: EffectID?
        var holdingReads = false
        var holdingWrites = false
        var nextRequest = 1
        var parked: [Int: CheckedContinuation<Void, Never>] = [:]
    }

    private let state: Locked<State>
    /// One entry per `selectedEffect()` call.
    public let reads = Collector<Void>()
    /// The ids `setSelectedEffect` was called with, in call order.
    public let writes = Collector<EffectID>()
    /// The calls that were parked (`holdReads()`, `holdWrites()`), in call order. A request is recorded
    /// in the same step that parks it, so a test that sees one can always complete it.
    public let heldRequests = Collector<Request>()

    public init(selected: EffectID? = nil) {
        state = Locked(State(selected: selected))
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

    private func parkIfHeld(_ call: Request.Call) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.withLock { state in
                let holding = call == .read ? state.holdingReads : state.holdingWrites
                guard holding else { return continuation.resume() }
                let id = state.nextRequest
                state.nextRequest += 1
                state.parked[id] = continuation
                heldRequests.append(Request(id: id, call: call, origin: ObjectIdentifier(self)))
            }
        }
    }
}
