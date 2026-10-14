import Domain
import TestSupport

/// `SettingsRepository` holding the chosen effect in memory: `selectedEffect()` answers
/// what was given at the start or last set, and `writes` records every
/// `setSelectedEffect`, in order, so a subject that must not persist is asserted to
/// have written nothing.
public final class FakeSettingsRepository: SettingsRepository, Sendable {
    private let stored: Locked<EffectID?>
    /// One entry per `selectedEffect()` call.
    public let reads = Collector<Void>()
    /// The ids `setSelectedEffect` was called with, in call order.
    public let writes = Collector<EffectID>()

    public init(selected: EffectID? = nil) {
        stored = Locked(selected)
    }

    public func selectedEffect() async -> EffectID? {
        reads.append(())
        return stored.current
    }

    public func setSelectedEffect(_ id: EffectID) async {
        stored.set(id)
        writes.append(id)
    }
}
