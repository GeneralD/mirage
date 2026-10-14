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

@Suite("FakeSettingsRepository")
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
