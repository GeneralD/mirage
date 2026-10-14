import Dependencies
import Domain
import EffectPackageRepository
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("BundledOnlyCatalog", .timeLimit(.minutes(1)))
struct BundledOnlyCatalogTests {
    private struct StubBundledEffects: BundledEffects {
        let defaultEffect: EffectSource
    }

    private let effect = EffectSource(name: "Chromatic Grain", source: "kernel void effect() {}")

    private func makeSubject() -> BundledOnlyCatalog {
        withDependencies {
            $0.bundledEffects = StubBundledEffects(defaultEffect: effect)
        } operation: {
            BundledOnlyCatalog()
        }
    }

    @Test("the catalog is the bundled default alone, ready, keyed by its name")
    func catalogIsTheBundledDefault() async {
        let subject = makeSubject()
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = Task { for await entries in subject.catalog() { seen.append(entries) } }
        await seen.waitForCount(1)
        consumer.cancel()
        await consumer.value

        let id = EffectID(origin: .bundled, key: "Chromatic Grain")
        #expect(seen.values == [[EffectCatalogEntry(id: id, displayName: "Chromatic Grain", origin: .bundled, availability: .ready)]])
    }

    @Test("it lists once and stays open: nothing changes it, and it ends when its consumer lets go")
    func listsOnceAndStaysOpen() async {
        let subject = makeSubject()
        let seen = Collector<[EffectCatalogEntry]>()
        let ended = Collector<Void>()
        let consumer = Task {
            for await entries in subject.catalog() { seen.append(entries) }
            ended.append(())
        }
        await seen.waitForCount(1)

        let changed = await tickUntil(50, tick: {}, until: { seen.count > 1 || ended.count > 0 })
        #expect(!changed, "no second listing and no end by itself")

        consumer.cancel()
        await ended.waitForCount(1)
        #expect(seen.count == 1)
    }

    @Test("source(of:) is the bundled default's source for its own id, and sourceMissing for any other")
    func sourceOfAnId() async {
        let subject = makeSubject()
        #expect(await subject.source(of: .bundled("Chromatic Grain")) == .success(effect))
        #expect(await subject.source(of: .bundled("Other")) == .failure(.sourceMissing))
        #expect(await subject.source(of: .package("Chromatic Grain")) == .failure(.sourceMissing), "a package of that name is not the bundled effect")
    }

    @Test("there is no folder to open, and opening it needs no DataSource: the unimplemented defaults would report one")
    func openFolderDoesNothing() {
        makeSubject().openEffectsFolder()
    }
}
