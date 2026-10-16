import Combine
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("InMemoryKeyValueStore")
struct InMemoryKeyValueStoreTests {
    @Test("set stores a string under a key, overwrites it, and removeValue takes it away")
    func setOverwriteRemove() {
        let store = InMemoryKeyValueStore()
        #expect(store.string(forKey: "selected") == nil)

        store.set("a", forKey: "selected")
        #expect(store.string(forKey: "selected") == "a")
        store.set("b", forKey: "selected")
        #expect(store.string(forKey: "selected") == "b")
        store.removeValue(forKey: "selected")
        #expect(store.string(forKey: "selected") == nil)
        store.removeValue(forKey: "never-set")
        #expect(store.values.isEmpty)
    }

    @Test("it starts with what it was given, and writes records the key of every set and remove, in order")
    func initialValuesAndWrites() {
        let store = InMemoryKeyValueStore(["seed": "1"])
        #expect(store.values == ["seed": "1"])
        #expect(store.writes.count == 0, "what it started with is not a write")

        store.set("x", forKey: "a")
        store.removeValue(forKey: "seed")
        #expect(store.writes.values == ["a", "seed"])
    }
}

@Suite("FakeWorkspaceGateway")
struct FakeWorkspaceGatewayTests {
    @Test("open records each path in order and opens nothing")
    func openIsRecorded() {
        let workspace = FakeWorkspaceGateway()
        workspace.open("/effects")
        workspace.open("/effects/a.lens")
        #expect(workspace.opened.values == ["/effects", "/effects/a.lens"])
    }
}

@Suite("FixedAppDirectories")
struct FixedAppDirectoriesTests {
    @Test("the effects directory is the one the test named")
    func effectsDirectory() {
        #expect(FixedAppDirectories(effectsDirectory: "/support/app/Effects").effectsDirectory == "/support/app/Effects")
    }
}

@Suite("FakeSettingsRepository", .timeLimit(.minutes(1)))
struct FakeSettingsRepositoryTests {
    @Test("selectedEffect answers what it was made with, then what was set, and both are recorded")
    func readsAndWrites() async {
        let settings = FakeSettingsRepository(selected: .bundled("Chromatic Grain"))
        #expect(await settings.selectedEffect() == .bundled("Chromatic Grain"))
        #expect(settings.writes.count == 0, "what it started with is not a write")

        await settings.setSelectedEffect(.package("glitch"))
        #expect(await settings.selectedEffect() == .package("glitch"))
        #expect(settings.writes.values == [.package("glitch")])
        #expect(settings.reads.count == 2)
    }

    @Test("nothing chosen is nil")
    func nothingChosen() async {
        #expect(await FakeSettingsRepository().selectedEffect() == nil)
    }

    @Test("a held read stays parked until it is completed, and answers what was stored when it began")
    func heldRead() async {
        let settings = FakeSettingsRepository(selected: .package("glitch"))
        settings.holdReads()
        let read = Task { await settings.selectedEffect() }
        await settings.heldRequests.waitForCount(1)
        let request = settings.heldRequests.values[0]
        #expect(request.call == .read)
        #expect(settings.pendingCount == 1)

        await settings.setSelectedEffect(.package("other"))  // not held: lands while the read is parked
        #expect(settings.complete(request))
        #expect(await read.value == .package("glitch"), "the read began before the write")
        #expect(settings.pendingCount == 0)
        settings.holdReads(false)
        #expect(await settings.selectedEffect() == .package("other"), "a read after the write sees it")
    }

    @Test("a held write has stored its value, and its caller waits until the call is completed")
    func heldWrite() async {
        let settings = FakeSettingsRepository()
        settings.holdWrites()
        let returned = Collector<Void>()
        let write = Task {
            await settings.setSelectedEffect(.package("glitch"))
            returned.append(())
        }
        await settings.heldRequests.waitForCount(1)
        let request = settings.heldRequests.values[0]
        #expect(request.call == .write(.package("glitch")))
        #expect(settings.writes.values == [.package("glitch")])
        #expect(await settings.selectedEffect() == .package("glitch"), "remembered already, though the call has not returned")
        #expect(returned.count == 0)

        #expect(settings.complete(request))
        await write.value
        #expect(returned.count == 1)
    }

    @Test("a request completes once, and one from another repository completes nothing")
    func completeOnce() async {
        let settings = FakeSettingsRepository()
        let stranger = FakeSettingsRepository()
        settings.holdReads()
        let read = Task { await settings.selectedEffect() }
        await settings.heldRequests.waitForCount(1)
        let request = settings.heldRequests.values[0]

        #expect(!stranger.complete(request), "ids restart at 1 per instance, so the id alone is not an identity")
        #expect(settings.pendingCount == 1)
        #expect(settings.complete(request))
        #expect(!settings.complete(request), "it was already resumed")
        _ = await read.value
    }

    @Test("holding can be switched off again: later calls answer at once, and the calls already parked stay parked")
    func releasingTheHold() async {
        let settings = FakeSettingsRepository(selected: .package("glitch"))
        settings.holdReads()
        let parked = Task { await settings.selectedEffect() }
        await settings.heldRequests.waitForCount(1)
        settings.holdReads(false)

        #expect(await settings.selectedEffect() == .package("glitch"), "answers at once now")
        #expect(settings.pendingCount == 1)
        #expect(settings.complete(settings.heldRequests.values[0]))
        _ = await parked.value
    }
}

@Suite("FakeEffectInteractor", .timeLimit(.minutes(1)))
struct FakeEffectInteractorTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let glitch = EffectCatalogEntry.fixture(.package("glitch"))

    @Test("state hands a subscriber the current state at once and every publish after it")
    func stateIsDrivenByPublish() async {
        let initial = EffectCatalogState.fixture([chromatic])
        let interactor = FakeEffectInteractor(state: initial)
        let seen = Collector<EffectCatalogState>()
        let subscription = interactor.state.sink { seen.append($0) }
        #expect(seen.values == [initial], "a subject replays its current value")

        let next = EffectCatalogState.fixture([chromatic, glitch], outcome: .prepared)
        interactor.publish(next)
        #expect(seen.values == [initial, next])

        let late = Collector<EffectCatalogState>()
        let lateSubscription = interactor.state.sink { late.append($0) }
        #expect(late.values == [next], "a subscriber after the publish starts with it")
        withExtendedLifetime((subscription, lateSubscription)) {}
    }

    @Test("commands are recorded and cause nothing")
    func commandsAreRecorded() {
        let interactor = FakeEffectInteractor(state: .fixture([chromatic]))
        interactor.start()
        interactor.select(.package("glitch"))
        interactor.openEffectsFolder()
        interactor.stop()
        interactor.stop()

        #expect(interactor.starts.count == 1)
        #expect(interactor.stops.count == 2)
        #expect(interactor.selections.values == [.package("glitch")])
        #expect(interactor.folderOpens.count == 1)
    }
}
