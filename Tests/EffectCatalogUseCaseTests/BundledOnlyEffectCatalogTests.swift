import Dependencies
import Domain
import EffectCatalogUseCase
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("BundledOnlyEffectCatalog", .timeLimit(.minutes(1)))
struct BundledOnlyEffectCatalogTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let glitch = EffectCatalogEntry.fixture(.package("glitch"))

    private func makeSubject(over repository: FakeEffectPackageRepository) -> BundledOnlyEffectCatalog {
        withDependencies {
            $0.effectPackageRepository = repository
        } operation: {
            BundledOnlyEffectCatalog()
        }
    }

    @Test("observe reports the catalog the Repository lists with its first entry selected, and no outcome yet")
    func observeReportsTheBundledState() async {
        let repository = FakeEffectPackageRepository(entries: [chromatic])
        let subject = makeSubject(over: repository)
        let seen = Collector<EffectCatalogState>()
        let consumer = Task { for await state in subject.observe() { seen.append(state) } }
        await seen.waitForCount(1)
        consumer.cancel()
        await consumer.value

        #expect(seen.values == [EffectCatalogState(entries: [chromatic], selection: chromatic.id, outcome: nil)])
    }

    @Test("it reports once and stays open: a later change of the catalog is not followed, and the stream ends with its consumer")
    func reportsOnceAndStaysOpen() async {
        let repository = FakeEffectPackageRepository(entries: [chromatic])
        let subject = makeSubject(over: repository)
        let seen = Collector<EffectCatalogState>()
        let ended = Collector<Void>()
        let consumer = Task {
            for await state in subject.observe() { seen.append(state) }
            ended.append(())
        }
        await seen.waitForCount(1)
        repository.publish([chromatic, glitch])

        let changed = await tickUntil(50, tick: {}, until: { seen.count > 1 || ended.count > 0 })
        #expect(!changed, "bundled-only is the state, whatever the Repository lists afterwards")

        consumer.cancel()
        await ended.waitForCount(1)
    }

    @Test("the Repository's catalog stream is let go as soon as the state is taken from it")
    func theCatalogStreamIsReleased() async {
        let repository = FakeEffectPackageRepository(entries: [chromatic])
        let subject = makeSubject(over: repository)
        let consumer = Task { for await _ in subject.observe() {} }
        await repository.terminations.waitForCount(1)
        consumer.cancel()
        await consumer.value
    }

    @Test("a consumer that lets go before the Repository has listed anything ends the wait for it")
    func cancelBeforeTheFirstListing() async {
        let repository = FakeEffectPackageRepository()
        let subject = makeSubject(over: repository)
        let consumer = Task { for await _ in subject.observe() {} }
        await repository.catalogRequests.waitForCount(1)

        consumer.cancel()
        await repository.terminations.waitForCount(1)
        await consumer.value
    }

    @Test("an empty listing has nothing to select: the state waits for the first one that has an entry")
    func emptyListingIsSkipped() async {
        let repository = FakeEffectPackageRepository(entries: [])
        let subject = makeSubject(over: repository)
        let seen = Collector<EffectCatalogState>()
        let consumer = Task { for await state in subject.observe() { seen.append(state) } }
        await repository.catalogRequests.waitForCount(1)
        repository.publish([glitch, chromatic])
        await seen.waitForCount(1)
        consumer.cancel()
        await consumer.value

        #expect(seen.values == [EffectCatalogState(entries: [glitch, chromatic], selection: glitch.id, outcome: nil)])
    }

    @Test("select is prepared for an effect the catalog lists, and unavailable for any other")
    func select() async {
        let subject = makeSubject(over: FakeEffectPackageRepository(entries: [chromatic]))
        #expect(await subject.select(chromatic.id) == .prepared)
        #expect(await subject.select(.package("glitch")) == .unavailable(nil))
    }

    @Test("run returns only when its task is cancelled")
    func runUntilCancelled() async {
        let subject = makeSubject(over: FakeEffectPackageRepository(entries: [chromatic]))
        let returned = Collector<Void>()
        let task = Task {
            await subject.run()
            returned.append(())
        }

        let returnedEarly = await tickUntil(50, tick: {}, until: { returned.count > 0 })
        #expect(!returnedEarly)
        task.cancel()
        await returned.waitForCount(1)
    }

    @Test("opening the folder is the Repository's")
    func openFolderIsDelegated() {
        let repository = FakeEffectPackageRepository(entries: [chromatic])
        makeSubject(over: repository).openEffectsFolder()
        #expect(repository.folderOpens.count == 1)
    }
}
