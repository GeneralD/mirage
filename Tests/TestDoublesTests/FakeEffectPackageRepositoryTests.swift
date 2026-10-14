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

    @Test("held, source(of:) is recorded at the call and parked until the test completes it, in any order, each exactly once")
    func heldSourcesAreManual() async throws {
        let repository = FakeEffectPackageRepository()
        let v1 = EffectSource(name: "Glitch", source: "glitch v1")
        let other = EffectSource(name: "Other", source: "other v1")
        repository.script(.success(v1), for: .package("glitch"))
        repository.script(.success(other), for: .package("other"))
        repository.holdSources()

        let first = Task { await repository.source(of: .package("glitch")) }
        await repository.heldSources.waitForCount(1)
        let second = Task { await repository.source(of: .package("other")) }
        await repository.heldSources.waitForCount(2)
        let requests = repository.heldSources.values
        #expect(requests.map(\.effect) == [.package("glitch"), .package("other")])
        #expect(repository.sourceRequests.values == [.package("glitch"), .package("other")])
        #expect(repository.pendingSourceCount == 2)

        #expect(repository.completeSource(requests[1]))
        #expect(await second.value == .success(other))
        #expect(repository.pendingSourceCount == 1, "the other read is still parked")
        #expect(repository.completeSource(requests[0]))
        #expect(await first.value == .success(v1))
        #expect(!repository.completeSource(requests[0]), "a second completion has nothing to resume")
        #expect(repository.pendingSourceCount == 0)
    }

    @Test("a held read answers what was scripted when it began, unless the test completes it with something else")
    func heldSourceAnswersWhatItSaw() async throws {
        let repository = FakeEffectPackageRepository()
        let v1 = EffectSource(name: "Glitch", source: "glitch v1")
        repository.script(.failure(.unreadable(message: "mid-save")), for: .package("glitch"))
        repository.holdSources()

        let early = Task { await repository.source(of: .package("glitch")) }
        await repository.heldSources.waitForCount(1)
        repository.script(.success(v1), for: .package("glitch"))
        let late = Task { await repository.source(of: .package("glitch")) }
        await repository.heldSources.waitForCount(2)
        let requests = repository.heldSources.values
        repository.completeSource(requests[0])
        repository.completeSource(requests[1], with: .failure(.manifestMissing))

        #expect(await early.value == .failure(.unreadable(message: "mid-save")), "the files as they were when this read began")
        #expect(await late.value == .failure(.manifestMissing), "the test's own answer wins")
    }

    @Test("reads made before the hold, and after it is lifted, answer at once; a request from another repository resumes nothing")
    func holdIsOptIn() async throws {
        let repository = FakeEffectPackageRepository()
        let stranger = FakeEffectPackageRepository()
        let v1 = EffectSource(name: "Glitch", source: "glitch v1")
        repository.script(.success(v1), for: .package("glitch"))
        stranger.script(.success(v1), for: .package("glitch"))

        #expect(await repository.source(of: .package("glitch")) == .success(v1), "not held by default")
        repository.holdSources()
        let parked = Task { await repository.source(of: .package("glitch")) }
        await repository.heldSources.waitForCount(1)
        repository.holdSources(false)
        #expect(await repository.source(of: .package("glitch")) == .success(v1), "the hold was lifted")
        #expect(repository.heldSources.count == 1)

        stranger.holdSources()
        let foreign = Task { await stranger.source(of: .package("glitch")) }
        await stranger.heldSources.waitForCount(1)
        let request = try #require(repository.heldSources.last)
        #expect(!stranger.completeSource(request), "ids restart at 1 per instance: the origin tells a stranger's request")
        #expect(stranger.pendingSourceCount == 1)
        #expect(repository.pendingSourceCount == 1, "and the other repository's parked read is untouched")

        repository.completeSource(request)
        stranger.completeSource(try #require(stranger.heldSources.last))
        _ = await (parked.value, foreign.value)
    }
}
