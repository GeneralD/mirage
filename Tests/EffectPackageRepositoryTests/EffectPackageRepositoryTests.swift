import Dependencies
import Domain
import EffectPackageRepository
import TestDoubles
import TestSupport
import Testing

/// The catalog Repository over `FakeEffectPackages` and `FakeEffectWatch`: the test
/// edits the folder under the subject (`packages.script`) and then fires the watch, so
/// every listing below is one the test caused, and nothing waits for a clock or a file.
/// A catalog is awaited with `Collector.waitForCount`. What the Repository decides is
/// what is proven here: the order, what a broken package looks like, when it lists
/// again and with which watch set, and what `source(of:)` answers; the folder reading
/// and the burst folding are the DataSources' own suites.
@Suite("EffectPackageRepository", .timeLimit(.minutes(1)))
struct EffectPackageRepositoryTests {
    private struct StubBundledEffects: BundledEffects {
        let defaultEffect: EffectSource
    }

    /// A watch that ends at once, as a stream the contract only ends on the consumer's say.
    private struct EndedWatch: EffectWatch {
        func changes(of watchSet: EffectWatchSet) -> AsyncStream<Void> {
            AsyncStream { $0.finish() }
        }
    }

    /// The folder as the Repository sees it, writing each listing it is asked for to the developer log
    /// with how many watches are still armed at that moment: a sequence the test can read back.
    private struct SequencedPackages: EffectPackages {
        let base: FakeEffectPackages
        let watch: FakeEffectWatch
        let log: RecordingLog

        func packages() async -> EffectPackageInventory {
            log.record(.effect, "listing the folder, \(watch.activeCount) armed")
            return await base.packages()
        }

        func package(_ id: EffectID) async -> EffectPackageListing? {
            await base.package(id)
        }

        func openFolder() {
            base.openFolder()
        }
    }

    /// The watch as the Repository sees it, writing each arming to the same log, the same way. The stream is
    /// the fake's own, so nothing about when it ends or yields changes.
    private struct SequencedWatch: EffectWatch {
        let base: FakeEffectWatch
        let log: RecordingLog

        func changes(of watchSet: EffectWatchSet) -> AsyncStream<Void> {
            log.record(.effect, "arming a watch, \(base.activeCount) armed")
            return base.changes(of: watchSet)
        }
    }

    private struct Rig {
        let packages: FakeEffectPackages
        let watch: FakeEffectWatch
        /// The two sinks are separate recorders, so a line is proven to have gone to the one it belongs to.
        let errors: RecordingLog
        let developer: RecordingLog
        let subject: EffectPackageRepositoryImpl

        /// With `sequenced`, the developer log also carries the Repository's calls on the folder and on the
        /// watch, in the order it made them, between the "catalog listed" lines it writes itself.
        init(inventory: EffectPackageInventory = .empty, effectWatch: (any EffectWatch)? = nil, sequenced: Bool = false) {
            let packages = FakeEffectPackages(inventory: inventory)
            let watch = FakeEffectWatch()
            let errors = RecordingLog()
            let developer = RecordingLog()
            self.packages = packages
            self.watch = watch
            self.errors = errors
            self.developer = developer
            subject = withDependencies {
                $0.effectPackages = sequenced ? SequencedPackages(base: packages, watch: watch, log: developer) : packages
                $0.effectWatch = effectWatch ?? (sequenced ? SequencedWatch(base: watch, log: developer) : watch)
                $0.bundledEffects = StubBundledEffects(defaultEffect: EffectPackageRepositoryTests.bundledEffect)
                $0.errorLog = errors
                $0.developerLog = developer
            } operation: {
                EffectPackageRepositoryImpl()
            }
        }

        /// Suspends until the catalog's task has done all its work, which it ends by recording that
        /// the catalog ended. What it logged or armed before that is there to be read, without a race.
        func waitForEnd() async {
            await developer.entries.waitFor { $0.message == "catalog ended" }
        }
    }

    private static let bundledEffect = EffectSource(name: "Chromatic Grain", source: "kernel void effect() {}")

    private static let bundledEntry = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    private static let glowSet = EffectWatchSet(
        directories: ["/effects", "/effects/glow.lens"],
        files: ["/effects/glow.lens/manifest.json", "/effects/glow.lens/effect.metal"])

    private static let bothSet = EffectWatchSet(
        directories: ["/effects", "/effects/glow.lens", "/effects/mist.lens"],
        files: [
            "/effects/glow.lens/manifest.json", "/effects/glow.lens/effect.metal",
            "/effects/mist.lens/manifest.json", "/effects/mist.lens/effect.metal",
        ])

    private static func ready(
        _ key: String, named name: String? = nil, by author: String? = nil, source: String = "kernel void effect() {}"
    ) -> EffectPackageListing {
        .ready(.fixture(.package(key), name: name, author: author, source: source))
    }

    private static func inventory(_ listings: [EffectPackageListing], watching set: EffectWatchSet = glowSet) -> EffectPackageInventory {
        EffectPackageInventory(listings: listings, watchSet: set)
    }

    /// A task that records every catalog the stream shows.
    private func listen(to stream: AsyncStream<[EffectCatalogEntry]>, into seen: Collector<[EffectCatalogEntry]>) -> Task<Void, Never> {
        Task { for await entries in stream { seen.append(entries) } }
    }

    /// The first catalog, taken as `BundledOnlyEffectCatalog.select` takes it: iterate once and let go.
    private func firstCatalog(of subject: EffectPackageRepositoryImpl) async -> [EffectCatalogEntry]? {
        for await entries in subject.catalog() { return entries }
        return nil
    }

    private func end(_ consumer: Task<Void, Never>) async {
        consumer.cancel()
        await consumer.value
    }

    // MARK: - The first catalog

    @Test("the first catalog comes without a change: the bundled effect first, then the package under its manifest name")
    func firstCatalogNeedsNoFire() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow", named: "Glow")]))
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: rig.subject.catalog(), into: seen)
        await seen.waitForCount(1)
        await end(consumer)

        #expect(seen.values == [[Self.bundledEntry, .fixture(.package("glow"), displayName: "Glow")]])
        #expect(rig.packages.listingCalls.count == 1)
    }

    @Test("a package shows its manifest's author; one whose manifest names none shows no author")
    func authorComesFromTheManifest() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow", named: "Glow", by: "Ada"), Self.ready("mist", named: "Mist")]))

        #expect(
            await firstCatalog(of: rig.subject) == [
                Self.bundledEntry,
                .fixture(.package("glow"), displayName: "Glow", author: "Ada"),
                .fixture(.package("mist"), displayName: "Mist"),
            ])
    }

    @Test("an empty folder is the bundled effect alone")
    func emptyFolder() async {
        let rig = Rig()
        #expect(await firstCatalog(of: rig.subject) == [Self.bundledEntry])
    }

    @Test("the folder is listed when the stream is made, before anyone iterates it")
    func listsEagerly() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]))
        let stream = rig.subject.catalog()
        await rig.packages.listingCalls.waitForCount(1)
        await rig.watch.requests.waitForCount(1)

        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: stream, into: seen)
        await seen.waitForCount(1)
        await end(consumer)
        #expect(seen.values == [[Self.bundledEntry, .fixture(.package("glow"))]], "what was listed before anyone looked is still there to be read")
        #expect(rig.packages.listingCalls.count == 1)
    }

    @Test("the watch for the listing is armed before the catalog is shown, so the first change after a catalog is heard")
    func armedBeforeShown() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]), sequenced: true)
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: rig.subject.catalog(), into: seen)
        await seen.waitForCount(1)

        // "catalog listed" is written right before the catalog is shown, so a watch armed after it was armed after the show.
        #expect(
            rig.developer.messages(in: .effect) == ["listing the folder, 0 armed", "arming a watch, 0 armed", "catalog listed: 2 entries, 0 broken"],
            "the folder is listed, the watch armed, and only then is the catalog shown")
        #expect(rig.watch.requests.values == [Self.glowSet], "armed with the set the inventory asked for")
        #expect(rig.watch.fire(), "a change right after the first catalog is heard")
        await seen.waitForCount(2)
        await end(consumer)
    }

    // MARK: - Order

    @Test(
        "the bundled effect is first and the packages follow by display name, whatever order the DataSource listed them in",
        arguments: [false, true])
    func orderedByDisplayName(reversed: Bool) async {
        // Folder names deliberately disagree with the names shown, so a sort by folder cannot pass.
        let listings: [EffectPackageListing] = [
            Self.ready("z-1", named: "apple"),
            Self.ready("a-2", named: "Cherry"),
            Self.ready("m-3", named: "banana"),
            Self.ready("b-4", named: "Effect 10"),
            Self.ready("c-5", named: "Effect 2"),
        ]
        let rig = Rig(inventory: Self.inventory(reversed ? listings.reversed() : listings))

        let entries = await firstCatalog(of: rig.subject)

        #expect(entries?.map(\.displayName) == ["Chromatic Grain", "apple", "banana", "Cherry", "Effect 2", "Effect 10"])
        #expect(entries?.map(\.id.key) == ["Chromatic Grain", "z-1", "m-3", "a-2", "c-5", "b-4"])
    }

    @Test(
        "the order does not consult the locale: names compare by their characters, so an accented one follows z on every machine",
        arguments: [false, true])
    func orderIgnoresTheLocale(reversed: Bool) async {
        // Most locales collate "ä" with "a" and "Émile" with "e", ahead of "z"; the characters alone put them after it.
        let listings: [EffectPackageListing] = [
            Self.ready("e", named: "Émile"),
            Self.ready("zed", named: "Zed"),
            Self.ready("a", named: "ä"),
            Self.ready("z", named: "z"),
        ]
        let rig = Rig(inventory: Self.inventory(reversed ? listings.reversed() : listings))

        let entries = await firstCatalog(of: rig.subject)

        #expect(entries?.dropFirst().map(\.displayName) == ["z", "Zed", "ä", "Émile"])
    }

    @Test("the bundled effect stays first when a package sorts before it, even one that shares its name")
    func bundledStaysFirst() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("chromatic", named: "Chromatic Grain"), Self.ready("aardvark", named: "Aardvark")]))

        let entries = await firstCatalog(of: rig.subject)

        #expect(
            entries == [
                Self.bundledEntry,
                .fixture(.package("aardvark"), displayName: "Aardvark"),
                .fixture(.package("chromatic"), displayName: "Chromatic Grain"),
            ])
        #expect(entries?.map(\.origin) == [.bundled, .package, .package])
    }

    @Test("two packages that show one name keep a fixed order, by folder name", arguments: [false, true])
    func equalNamesKeepAFixedOrder(reversed: Bool) async {
        let listings: [EffectPackageListing] = [Self.ready("b", named: "Twin"), Self.ready("a", named: "Twin"), Self.ready("c", named: "twin")]
        let rig = Rig(inventory: Self.inventory(reversed ? listings.reversed() : listings))

        let entries = await firstCatalog(of: rig.subject)

        #expect(entries?.dropFirst().map(\.id.key) == ["a", "b", "c"])
    }

    // MARK: - Broken packages

    @Test("a broken package is listed, under its folder name, with its problem, and sorts among the others")
    func brokenPackagesAreCarried() async {
        let invalid = EffectPackageProblem.manifestInvalid(message: "name is missing")
        let rig = Rig(
            inventory: Self.inventory([
                .broken(.package("zeta"), invalid),
                Self.ready("mid", named: "Mid"),
                .broken(.package("alpha"), .sourceMissing),
            ]))

        let entries = await firstCatalog(of: rig.subject)

        #expect(
            entries == [
                Self.bundledEntry,
                .fixture(.package("alpha"), availability: .broken(.sourceMissing)),
                .fixture(.package("mid"), displayName: "Mid"),
                .fixture(.package("zeta"), availability: .broken(invalid)),
            ])
    }

    @Test("each listing is logged for the developer with its size and how many packages are broken, and none is an error")
    func listingsAreLogged() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow"), .broken(.package("mist"), .manifestMissing)]))
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: rig.subject.catalog(), into: seen)
        await seen.waitForCount(1)
        rig.packages.script(Self.inventory([Self.ready("glow"), Self.ready("mist")]))
        #expect(rig.watch.fire())
        await seen.waitForCount(2)
        await end(consumer)
        await rig.waitForEnd()

        #expect(
            rig.developer.messages(in: .effect) == ["catalog listed: 3 entries, 1 broken", "catalog listed: 3 entries, 0 broken", "catalog ended"])
        #expect(rig.errors.entries.count == 0, "a listing is not an error")
    }

    // MARK: - Listing again

    @Test("a change lists again and arms a watch for the new inventory's set; the old watch is let go")
    func changeListsAgainAndRearms() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]))
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: rig.subject.catalog(), into: seen)
        await seen.waitForCount(1)

        rig.packages.script(Self.inventory([Self.ready("glow"), Self.ready("mist")], watching: Self.bothSet))
        #expect(rig.watch.fire())
        await seen.waitForCount(2)
        await rig.watch.terminations.waitForCount(1)

        #expect(seen.values.last == [Self.bundledEntry, .fixture(.package("glow")), .fixture(.package("mist"))])
        #expect(rig.packages.listingCalls.count == 2)
        #expect(rig.watch.requests.values == [Self.glowSet, Self.bothSet], "the second round is watched by the second inventory's set")
        #expect(rig.watch.terminations.values == [0], "the first watch is the one that ended")
        #expect(rig.watch.activeCount == 1)
        await end(consumer)
    }

    @Test("the old watch is let go before the folder is listed again, so no watch is armed while the folder is read")
    func oldWatchIsLetGoBeforeTheNextListing() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]), sequenced: true)
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: rig.subject.catalog(), into: seen)
        await seen.waitForCount(1)

        rig.packages.script(Self.inventory([Self.ready("glow"), Self.ready("mist")], watching: Self.bothSet))
        #expect(rig.watch.fire())
        await seen.waitForCount(2)
        let sequence = rig.developer.messages(in: .effect)
        await end(consumer)

        #expect(
            sequence == [
                "listing the folder, 0 armed", "arming a watch, 0 armed", "catalog listed: 2 entries, 0 broken",
                "listing the folder, 0 armed", "arming a watch, 0 armed", "catalog listed: 3 entries, 0 broken",
            ],
            "each round starts with no watch armed: the second one lists, then arms, with the first already let go")
    }

    @Test("a package that goes away leaves the catalog, and the watch it had is replaced")
    func removalListsAgain() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow"), Self.ready("mist")], watching: Self.bothSet))
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: rig.subject.catalog(), into: seen)
        await seen.waitForCount(1)

        rig.packages.script(Self.inventory([Self.ready("mist")], watching: Self.glowSet))
        #expect(rig.watch.fire())
        await seen.waitForCount(2)
        await end(consumer)

        #expect(seen.values.map { $0.map(\.id.key) } == [["Chromatic Grain", "glow", "mist"], ["Chromatic Grain", "mist"]])
        #expect(rig.watch.requests.values == [Self.bothSet, Self.glowSet])
    }

    @Test("every change is a listing, shown even when it equals the one before: the Repository folds nothing")
    func everyChangeIsShown() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]))
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: rig.subject.catalog(), into: seen)
        await seen.waitForCount(1)

        // Armed before each catalog is shown, so a fire after one is heard by the next round's watch.
        #expect(rig.watch.fire())
        await seen.waitForCount(2)
        #expect(rig.watch.fire())
        await seen.waitForCount(3)
        await end(consumer)

        #expect(seen.count == 3)
        #expect(Set(seen.values).count == 1, "the three catalogs are one and the same")
        #expect(rig.packages.listingCalls.count == 3)
        #expect(rig.watch.requests.count == 3)
    }

    // MARK: - Ending

    @Test("when the consumer lets go, the watch it was under ends too, and nothing lists again")
    func endingEndsTheWatch() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]))
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: rig.subject.catalog(), into: seen)
        await seen.waitForCount(1)

        await end(consumer)
        await rig.waitForEnd()

        #expect(rig.watch.terminations.values == [0])
        #expect(rig.watch.activeCount == 0)
        #expect(!rig.watch.fire(), "no stream is left to hear a change")
        #expect(rig.packages.listingCalls.count == 1)
        #expect(rig.errors.entries.count == 0, "the consumer letting go is not a watch lost")
    }

    @Test("the watch that ends is the current one, however many times the catalog was listed before")
    func endingAfterAChangeEndsTheLatestWatch() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]))
        let seen = Collector<[EffectCatalogEntry]>()
        let consumer = listen(to: rig.subject.catalog(), into: seen)
        await seen.waitForCount(1)
        #expect(rig.watch.fire())
        await seen.waitForCount(2)

        await end(consumer)
        await rig.waitForEnd()

        #expect(rig.watch.terminations.values.sorted() == [0, 1], "each watch ended exactly once")
        #expect(rig.watch.activeCount == 0)
        #expect(rig.errors.entries.count == 0, "the consumer letting go is not a watch lost")
    }

    @Test("a consumer that takes the first catalog and stops leaves no watch behind")
    func firstCatalogOnlyLeavesNothingArmed() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]))

        #expect(await firstCatalog(of: rig.subject) != nil)
        await rig.waitForEnd()

        #expect(rig.watch.requests.count == 1)
        #expect(rig.watch.terminations.values == [0])
        #expect(rig.watch.activeCount == 0)
        #expect(rig.errors.entries.count == 0, "taking one catalog and stopping is not a watch lost")
    }

    @Test("a catalog made and dropped without ever being iterated stops the work and leaves no watch armed")
    func droppedWithoutIterating() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]))

        _ = rig.subject.catalog()
        await rig.waitForEnd()

        // Eager: the task may have been cancelled before or after it armed a watch, so the count is not fixed.
        #expect(rig.watch.activeCount == 0, "no watch is left armed")
        #expect(rig.watch.requests.count == rig.watch.terminations.count, "every watch it armed was let go")
        #expect(rig.errors.entries.count == 0, "dropping the stream is not a watch lost")
    }

    @Test("a watch that ends by itself ends the catalog with a logged error, and the folder is not listed in a loop")
    func watchEndingByItself() async {
        let rig = Rig(inventory: Self.inventory([Self.ready("glow")]), effectWatch: EndedWatch())

        let shown = await rig.subject.catalog().reduce(into: [[EffectCatalogEntry]]()) { $0.append($1) }

        #expect(shown == [[Self.bundledEntry, .fixture(.package("glow"))]], "the catalog it did list is still delivered")
        #expect(rig.packages.listingCalls.count == 1)
        #expect(rig.errors.messages(in: .effect).contains { $0.contains("watch ended on its own") }, "the lost watch is an error")
        #expect(!rig.developer.contains("watch ended on its own"), "and only the error log has it")
        #expect(rig.developer.messages(in: .effect).last == "catalog ended", "the catalog says it is over, whichever side ended it")
    }

    // MARK: - source(of:)

    @Test("the bundled effect's source is the bundled default, and no package is read for it")
    func bundledSource() async {
        let rig = Rig()

        #expect(await rig.subject.source(of: .bundled("Chromatic Grain")) == .success(Self.bundledEffect))
        #expect(rig.packages.packageRequests.count == 0)
    }

    @Test("a bundled id the app does not ship is sourceMissing, and a package of the bundled effect's name is not the bundled effect")
    func unknownBundledSource() async {
        let rig = Rig()

        #expect(await rig.subject.source(of: .bundled("Other")) == .failure(.sourceMissing))
        #expect(rig.packages.packageRequests.count == 0)
        #expect(
            await rig.subject.source(of: .package("Chromatic Grain")) == .failure(.manifestMissing),
            "that id is a package id, and the folder has none")
    }

    @Test("a ready package's source is the one its listing carries")
    func readyPackageSource() async {
        let rig = Rig()
        rig.packages.script(Self.ready("glow", named: "Glow", source: "kernel void effect() { /* glow */ }"), for: .package("glow"))

        let result = await rig.subject.source(of: .package("glow"))

        #expect(result == .success(EffectSource(name: "Glow", source: "kernel void effect() { /* glow */ }")))
        #expect(rig.packages.packageRequests.values == [.package("glow")])
    }

    @Test("a broken package answers its own problem")
    func brokenPackageSource() async {
        let rig = Rig()
        let problem = EffectPackageProblem.unreadable(message: "permission denied")
        rig.packages.script(.broken(.package("glow"), problem), for: .package("glow"))

        #expect(await rig.subject.source(of: .package("glow")) == .failure(problem))
    }

    @Test("a package the folder no longer has is manifestMissing")
    func missingPackageSource() async {
        let rig = Rig()

        #expect(await rig.subject.source(of: .package("gone")) == .failure(.manifestMissing))
        #expect(rig.packages.packageRequests.values == [.package("gone")])
    }

    @Test("a package is read afresh on every call, so an edit shows in the next read")
    func packageSourceIsNeverCached() async {
        let rig = Rig()
        rig.packages.script(Self.ready("glow", source: "// v1"), for: .package("glow"))
        #expect(await rig.subject.source(of: .package("glow")) == .success(EffectSource(name: "glow", source: "// v1")))

        rig.packages.script(Self.ready("glow", source: "// v2"), for: .package("glow"))
        #expect(await rig.subject.source(of: .package("glow")) == .success(EffectSource(name: "glow", source: "// v2")))

        rig.packages.script(.broken(.package("glow"), .sourceMissing), for: .package("glow"))
        #expect(await rig.subject.source(of: .package("glow")) == .failure(.sourceMissing))
        #expect(rig.packages.packageRequests.count == 3)
    }

    @Test("reading a source lists nothing and arms nothing")
    func sourceDoesNotList() async {
        let rig = Rig()
        _ = await rig.subject.source(of: .package("glow"))
        _ = await rig.subject.source(of: .bundled("Chromatic Grain"))

        #expect(rig.packages.listingCalls.count == 0)
        #expect(rig.watch.requests.count == 0)
    }

    // MARK: - Opening the folder

    @Test("opening the effects folder is the DataSource's: one call through, nothing listed")
    func openFolderPassesThrough() {
        let rig = Rig()

        rig.subject.openEffectsFolder()

        #expect(rig.packages.folderOpens.count == 1)
        #expect(rig.packages.listingCalls.count == 0)
    }
}
