import Domain
import TestDoubles
import TestSupport
import Testing

/// What the effects menu's policy does with a package's thumbnail (#12): nothing but carry it. The
/// state's entries are the catalog's, picture included, and a listing that changes only a picture is
/// a new state that prepares nothing.
@Suite("EffectCatalogUseCase thumbnails", .timeLimit(.minutes(1)))
struct EffectCatalogThumbnailTests {
    private typealias Rig = EffectCatalogRig

    private static func glitch(_ thumbnail: EffectThumbnail?) -> EffectCatalogEntry {
        .fixture(Rig.glitch.id, displayName: Rig.glitch.displayName, thumbnail: thumbnail)
    }

    @Test("the state's entries carry each package's thumbnail as the catalog listed it")
    func stateCarriesTheThumbnail() async {
        let picture = EffectThumbnail.fixture(3)
        let rig = Rig(entries: [Rig.bundled, Self.glitch(picture), Rig.other])
        let watcher = rig.watch()
        let run = rig.start()

        await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(watcher.states.values == [Rig.state([Rig.bundled, Self.glitch(picture), Rig.other])])
        await rig.stop(run)
    }

    @Test("a listing that replaces only a thumbnail, of the chosen package or another, publishes a new state and prepares nothing")
    func replacedThumbnailPublishesAndPreparesNothing() async {
        let first = EffectThumbnail.fixture(1)
        let second = EffectThumbnail.fixture(2, format: .jpeg)
        let rig = Rig(entries: [Rig.bundled, Self.glitch(first), Rig.other], persisted: Rig.glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.publish([Rig.bundled, Self.glitch(second), Rig.other])
        await watcher.states.waitForCount(2)
        rig.packages.publish([Rig.bundled, Self.glitch(nil), Rig.other])
        await watcher.states.waitForCount(3)

        #expect(
            watcher.states.values == [
                Rig.state([Rig.bundled, Self.glitch(first), Rig.other], selection: Rig.glitch),
                Rig.state([Rig.bundled, Self.glitch(second), Rig.other], selection: Rig.glitch),
                Rig.state([Rig.bundled, Self.glitch(nil), Rig.other], selection: Rig.glitch),
            ])
        #expect(rig.runtime.prepareRequests.count == 1, "a picture is not a source: nothing was prepared again")
        await rig.stop(run)
    }
}
