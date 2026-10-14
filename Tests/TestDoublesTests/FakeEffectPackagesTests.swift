import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectPackages")
struct FakeEffectPackagesTests {
    private let glitch = EffectPackage.fixture(.package("glitch"))
    private let blur = EffectPackage.fixture(.package("blur"))

    @Test("packages answers the inventory it was made with, and the one scripted since, and counts the calls")
    func packagesAnswersTheInventory() async {
        let first = EffectPackageInventory(listings: [.ready(glitch)], watchSet: EffectWatchSet(directories: ["/effects"], files: []))
        let packages = FakeEffectPackages(inventory: first)
        #expect(await packages.packages() == first)

        let second = EffectPackageInventory(listings: [.ready(glitch), .ready(blur)], watchSet: .empty)
        packages.script(second)
        #expect(await packages.packages() == second)
        #expect(packages.listingCalls.count == 2)
    }

    @Test("package(id) finds the listing in the inventory, and nil for an id nothing lists")
    func packageFallsBackToTheInventory() async {
        let packages = FakeEffectPackages(inventory: EffectPackageInventory(listings: [.ready(glitch), .broken(.package("old"), .sourceMissing)], watchSet: .empty))
        #expect(await packages.package(.package("glitch")) == .ready(glitch))
        #expect(await packages.package(.package("old")) == .broken(.package("old"), .sourceMissing))
        #expect(await packages.package(.package("nobody")) == nil)
        #expect(packages.packageRequests.values == [.package("glitch"), .package("old"), .package("nobody")])
    }

    @Test("a listing scripted for an id wins over the inventory, and nil takes the override away")
    func perIdOverride() async {
        let packages = FakeEffectPackages(inventory: EffectPackageInventory(listings: [.ready(glitch)], watchSet: .empty))
        packages.script(.broken(.package("glitch"), .unreadable(message: "half written")), for: .package("glitch"))
        #expect(await packages.package(.package("glitch")) == .broken(.package("glitch"), .unreadable(message: "half written")))

        packages.script(nil, for: .package("glitch"))
        #expect(await packages.package(.package("glitch")) == .ready(glitch))
    }

    @Test("openFolder is recorded")
    func openFolderIsRecorded() {
        let packages = FakeEffectPackages()
        packages.openFolder()
        #expect(packages.folderOpens.count == 1)
    }
}
