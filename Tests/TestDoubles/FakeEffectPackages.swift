import Domain
import TestSupport

/// `EffectPackages` answering from what the test scripted, at once: `packages()` the
/// inventory, `package(id)` the listing scripted for that id, or else the one the
/// inventory holds, or `nil`. Re-scripting between calls is how a test edits the
/// folder under a subject; every call is recorded, so "listed again after the change"
/// is a count.
public final class FakeEffectPackages: EffectPackages, Sendable {
    private struct State {
        var inventory: EffectPackageInventory
        var listings: [EffectID: EffectPackageListing] = [:]
    }

    private let state: Locked<State>
    /// One entry per `packages()` call.
    public let listingCalls = Collector<Void>()
    /// The ids `package(_:)` was asked for, in call order.
    public let packageRequests = Collector<EffectID>()
    /// One entry per `openFolder()` call.
    public let folderOpens = Collector<Void>()

    public init(inventory: EffectPackageInventory = .empty) {
        state = Locked(State(inventory: inventory))
    }

    /// Replaces the inventory `packages()` answers (and `package(_:)` falls back to).
    public func script(_ inventory: EffectPackageInventory) {
        state.withLock { $0.inventory = inventory }
    }

    /// Makes `package(id)` answer `listing`, whatever the inventory says; `nil` removes
    /// the override.
    public func script(_ listing: EffectPackageListing?, for id: EffectID) {
        state.withLock { $0.listings[id] = listing }
    }

    public func packages() async -> EffectPackageInventory {
        listingCalls.append(())
        return state.withLock { $0.inventory }
    }

    public func package(_ id: EffectID) async -> EffectPackageListing? {
        packageRequests.append(id)
        return state.withLock { $0.listings[id] ?? $0.inventory.listings.first { $0.id == id } }
    }

    public func openFolder() {
        folderOpens.append(())
    }
}
