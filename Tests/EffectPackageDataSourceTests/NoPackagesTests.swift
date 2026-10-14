import Domain
import EffectPackageDataSource
import TestDoubles
import Testing

@Suite("NoPackages")
struct NoPackagesTests {
    private let subject = NoPackages()

    @Test("the folder lists as empty and there is nothing to watch")
    func emptyInventory() async {
        let inventory = await subject.packages()
        #expect(inventory.listings.isEmpty)
        #expect(inventory.watchSet == EffectWatchSet(directories: [], files: []))
    }

    @Test("no package is found, whatever the id")
    func noPackage() async {
        #expect(await subject.package(.package("glitch")) == nil)
        #expect(await subject.package(.bundled("Chromatic Grain")) == nil)
    }

    @Test("opening the folder does nothing, and needs no gateway: the unimplemented defaults would report one")
    func openFolderDoesNothing() {
        subject.openFolder()
    }
}
