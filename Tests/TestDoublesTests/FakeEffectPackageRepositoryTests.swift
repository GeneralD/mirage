import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectPackageRepository", .timeLimit(.minutes(1)))
struct FakeEffectPackageRepositoryTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let glitch = EffectCatalogEntry.fixture(.package("glitch"))

    @Test("catalog starts with the entries the fake was made with, then yields every publish")
    func startsCurrentThenPublishes() async {
        let repository = FakeEffectPackageRepository(entries: [chromatic])
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = Task { for await entries in repository.catalog() { seen.append(entries) } }
        await seen.waitForCount(1)

        repository.publish([chromatic, glitch])
        await seen.waitForCount(2)
        consumer.cancel()
        await consumer.value
        #expect(seen.values == [[chromatic], [chromatic, glitch]])
    }

    @Test("a stream opened after a publish starts with it, and one with nothing to start from yields nothing yet")
    func lateStreamAndEmptyFake() async {
        let repository = FakeEffectPackageRepository()
        let early = Collector<[EffectCatalogEntry]>()
        let earlyConsumer = Task { for await entries in repository.catalog() { early.append(entries) } }
        await repository.catalogRequests.waitForCount(1)
        #expect(early.count == 0, "nothing published, nothing yielded")

        repository.publish([glitch])
        let late = Collector<[EffectCatalogEntry]>()
        let lateConsumer = Task { for await entries in repository.catalog() { late.append(entries) } }
        await late.waitForCount(1)
        await early.waitForCount(1)

        earlyConsumer.cancel()
        lateConsumer.cancel()
        await earlyConsumer.value
        await lateConsumer.value
        #expect(late.values == [[glitch]])
        #expect(early.values == [[glitch]])
    }

    @Test("a stream that ends is recorded and hears nothing more")
    func terminationIsRecorded() async {
        let repository = FakeEffectPackageRepository(entries: [chromatic])
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = Task { for await entries in repository.catalog() { seen.append(entries) } }
        await seen.waitForCount(1)

        consumer.cancel()
        await repository.terminations.waitForCount(1)
        repository.publish([glitch])
        await consumer.value
        #expect(seen.count == 1)
    }

    @Test("source(of:) answers what was scripted for the id and records the request")
    func scriptedSources() async {
        let repository = FakeEffectPackageRepository()
        let source = EffectSource(name: "Glitch", source: "kernel void effect() {}")
        repository.script(.success(source), for: .package("glitch"))
        repository.script(.failure(.manifestMissing), for: .package("broken"))

        #expect(await repository.source(of: .package("glitch")) == .success(source))
        #expect(await repository.source(of: .package("broken")) == .failure(.manifestMissing))
        #expect(repository.sourceRequests.values == [.package("glitch"), .package("broken")])
    }

    @Test("an id nobody scripted is a reported issue and answers sourceMissing")
    func unscriptedSource() async {
        let repository = FakeEffectPackageRepository()
        await withKnownIssue("a source nobody scripted is reported") {
            #expect(await repository.source(of: .package("surprise")) == .failure(.sourceMissing))
        }
    }

    @Test("openEffectsFolder is recorded")
    func openFolderIsRecorded() {
        let repository = FakeEffectPackageRepository()
        repository.openEffectsFolder()
        #expect(repository.folderOpens.count == 1)
    }
}
