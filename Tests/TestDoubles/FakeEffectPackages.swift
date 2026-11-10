import Dependencies
import Domain
import TestSupport

/// `EffectPackages` answering from what the test scripted, at once: `packages()` the
/// inventory, `package(id)` the listing scripted for that id, or else the one the
/// inventory holds, or `nil`. Re-scripting between calls is how a test edits the
/// folder under a subject; every call is recorded, so "listed again after the change"
/// is a count. `scaffold` answers the result scripted with `scriptScaffold`, and records its request.
public final class FakeEffectPackages: EffectPackages, Sendable {
    /// One `scaffold` call: the name and the folder it was asked for.
    public struct ScaffoldRequest: Sendable, Equatable {
        public let name: String
        public let folder: String

        public init(name: String, folder: String) {
            self.name = name
            self.folder = folder
        }
    }

    private struct State {
        var inventory: EffectPackageInventory
        var listings: [EffectID: EffectPackageListing] = [:]
        var pathListings: [String: EffectPackageListing] = [:]
        var scaffoldResult: Result<String, ScaffoldProblem>? = nil
    }

    private let state: Locked<State>
    /// One entry per `packages()` call.
    public let listingCalls = Collector<Void>()
    /// The ids `package(_:)` was asked for, in call order.
    public let packageRequests = Collector<EffectID>()
    /// The paths `package(atPath:)` was asked for, in call order.
    public let pathRequests = Collector<String>()
    /// The name and folder each `scaffold` call was asked for, in call order.
    public let scaffoldRequests = Collector<ScaffoldRequest>()
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

    /// Makes `package(atPath:)` answer `listing` for `path`, and nothing for any other path; `nil` removes
    /// the script.
    public func script(_ listing: EffectPackageListing?, atPath path: String) {
        state.withLock { $0.pathListings[path] = listing }
    }

    public func packages() async -> EffectPackageInventory {
        listingCalls.append(())
        return state.withLock { $0.inventory }
    }

    public func package(_ id: EffectID) async -> EffectPackageListing? {
        packageRequests.append(id)
        return state.withLock { $0.listings[id] ?? $0.inventory.listings.first { $0.id == id } }
    }

    public func package(atPath path: String) async -> EffectPackageListing? {
        pathRequests.append(path)
        return state.withLock { $0.pathListings[path] }
    }

    /// Makes `scaffold` answer `result` from now on, until it is scripted again.
    public func scriptScaffold(_ result: Result<String, ScaffoldProblem>) {
        state.withLock { $0.scaffoldResult = result }
    }

    public func scaffold(named name: String, in folder: String) async -> Result<String, ScaffoldProblem> {
        scaffoldRequests.append(ScaffoldRequest(name: name, folder: folder))
        guard let result = state.withLock({ $0.scaffoldResult }) else {
            reportIssue("FakeEffectPackages: no scaffold result scripted")
            return .failure(.unwritable(path: folder))
        }
        return result
    }

    public func openFolder() {
        folderOpens.append(())
    }
}
