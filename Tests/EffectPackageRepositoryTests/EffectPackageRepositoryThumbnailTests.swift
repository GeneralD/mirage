import Dependencies
import Domain
import EffectPackageRepository
import TestDoubles
import TestSupport
import Testing

/// What the catalog Repository does with a package's thumbnail (#12): it is carried into the
/// package's entry as the listing read it, and a listing that changes only a thumbnail is a new
/// catalog. Over `FakeEffectPackages` and `FakeEffectWatch`, as `EffectPackageRepositoryTests`.
@Suite("EffectPackageRepository thumbnails", .timeLimit(.minutes(1)))
struct EffectPackageRepositoryThumbnailTests {
    private struct StubBundledEffects: BundledEffects {
        let defaultEffect: EffectSource
    }

    private static let bundled = EffectSource(name: "Chromatic Grain", source: "kernel void effect() {}")
    private static let bundledEntry = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private static let watchSet = EffectWatchSet(directories: ["/effects"], files: [])

    private let packages = FakeEffectPackages()
    private let watch = FakeEffectWatch()

    private var subject: EffectPackageRepositoryImpl {
        withDependencies {
            $0.effectPackages = packages
            $0.effectWatch = watch
            $0.bundledEffects = StubBundledEffects(defaultEffect: Self.bundled)
        } operation: {
            EffectPackageRepositoryImpl()
        }
    }

    private static func inventory(_ listings: [EffectPackageListing]) -> EffectPackageInventory {
        EffectPackageInventory(listings: listings, watchSet: watchSet)
    }

    @Test("a ready package's entry carries the thumbnail it was read with; a package without one, a broken one and the bundled effect have none")
    func thumbnailReachesTheEntry() async {
        let picture = EffectThumbnail.fixture(7, format: .jpeg)
        packages.script(
            Self.inventory([
                .ready(.fixture(.package("glow"), name: "Glow", thumbnail: picture)),
                .ready(.fixture(.package("mist"), name: "Mist")),
                .broken(.package("torn"), .sourceMissing),
            ]))

        var catalogs = subject.catalog().makeAsyncIterator()
        let first = await catalogs.next()

        #expect(
            first == [
                Self.bundledEntry,
                .fixture(.package("glow"), displayName: "Glow", thumbnail: picture),
                .fixture(.package("mist"), displayName: "Mist"),
                .fixture(.package("torn"), availability: .broken(.sourceMissing)),
            ])
    }

    @Test("a change that replaces only a package's thumbnail lists a catalog with the new one")
    func replacedThumbnailIsANewCatalog() async {
        let before = EffectThumbnail.fixture(1)
        let after = EffectThumbnail.fixture(2)
        packages.script(Self.inventory([.ready(.fixture(.package("glow"), name: "Glow", thumbnail: before))]))
        let seen = Collector<[EffectCatalogEntry]>()
        let stream = subject.catalog()
        let consumer = Task { for await entries in stream { seen.append(entries) } }
        await seen.waitForCount(1)

        packages.script(Self.inventory([.ready(.fixture(.package("glow"), name: "Glow", thumbnail: after))]))
        #expect(watch.fire())
        await seen.waitForCount(2)
        consumer.cancel()
        await consumer.value

        #expect(seen.values.map { $0.last?.thumbnail } == [before, after])
        #expect(seen.values[0] != seen.values[1], "the two catalogs differ by the picture alone")
    }
}
