import BundledEffectDataSource
import Domain
import ShaderCompilationDataSource
import TestDoubles
import TestSupport
import Testing

/// The effects menu's whole flow on the loopback (epic #42, the completion condition of #52):
/// the real catalog (`LoopbackRig(effects: .real, catalog: .real)`: `EffectCatalogUseCaseImpl` over
/// the real Repository, DataSources, settings chain and effect runtime) with only the OS boundary
/// faked, joined to the extension by `InMemoryFrameTransport` in place of Mach. A package is written
/// into the folder the way an editor would, the watch is fired, and time is the catalog's clock
/// (`CatalogSide.clock`): what the device adds is the file events themselves, the Metal compile and
/// the screen, which Lane 1 of `.claude/rules/dev-verification.md` checks.
///
/// What each test judges is what reaches the extension: the pass graph the fake GPU recorded says
/// which library the frame was drawn with, and the surface the extension streamed says whether it
/// is that pass's output or the camera's own frame.
///
/// Nothing here sleeps or reads a clock: the host's executor is pumped by `tickUntil` (the runtime's
/// state hops onto it), the GPU completes by hand, the quiet period runs out when the test advances
/// the catalog's `GatedClock` after the sleep is parked (and that it has not run out a millisecond
/// earlier is read off the clock's `parkedCount`, not waited for), and an edit is waited for by what it
/// causes (a state, a compile that finished), never by time.
@MainActor
@Suite("Effect catalog on the loopback", .timeLimit(.minutes(1)))
struct EffectCatalogIntegrationTests {
    // MARK: 1. A package written into the folder appears in the catalog

    @Test("a package written into the folder appears in the catalog once the quiet period is over, and not before")
    func aWrittenPackageAppearsAfterTheQuietPeriod() async throws {
        let session = try await Session.start()
        let side = session.side
        let first = try #require(side.states.values.first)
        #expect(first.entries.map(\.id) == [Self.bundledID], "the folder was empty: the bundled effect alone")
        #expect(first.selection == Self.bundledID)
        #expect(first.outcome == .prepared, "the first state is published after the runtime has answered")
        #expect(side.fileSystem.createdDirectories.values == [CatalogSide.folder], "the first listing made the folder")
        #expect(side.fileWatch.activeWatches.contains(.init(kind: .directory, path: CatalogSide.folder)), "...and watches it")

        Neon.write(into: side.fileSystem, source: Neon.first)
        await session.rig.fireWatch(CatalogSide.folder)
        let published = side.states.count
        // The period is read off the clock, not waited out: the sleep the event started is still parked
        // one millisecond before 200 ms and gone at 200 ms, whatever the machine's load.
        side.clock.advance(by: .milliseconds(199))
        #expect(side.clock.parkedCount == 1, "the catalog's quiet period is still running at 199 ms")
        #expect(side.states.count == published, "the catalog lists again only when the files have been quiet for the whole period")

        side.clock.advance(by: .milliseconds(1))
        #expect(side.clock.parkedCount == 0, "...and it ends at 200 ms")
        #expect(await session.rig.pumpHost(until: { side.states.count > published }))
        let state = try #require(side.states.last)
        let entry = try #require(state.entries.last)
        #expect(state.entries.map(\.id) == [Self.bundledID, Neon.id], "the bundled effect first, then the package")
        #expect(entry.displayName == "Neon")
        #expect(entry.author == "Example Author")
        #expect(entry.availability == .ready)
        #expect(entry.origin == .package)
        #expect(state.selection == Self.bundledID, "listing a package chooses nothing")
        #expect(session.rig.host.shaders.calls.count == 1, "...and compiles nothing")

        try await session.finish()
        #expect(session.rig.host.errors.entries.count == 0)
    }

    // MARK: 2. Choosing it compiles it, and the extension gets a frame drawn with its library

    @Test("choosing the package compiles it once and the extension receives a frame drawn with its library")
    func choosingThePackageDrawsTheNextFrameWithIt() async throws {
        let session = try await Session.start()
        let rig = session.rig
        #expect(await session.install(source: Neon.first))

        #expect(await rig.choose(Neon.id) == .prepared)

        #expect(Self.compiledEffects(of: rig) == ["bundled", "neon first"], "the bundled effect at the start, then the package, once")
        // The answer and the state reach the test on different tasks (the observer appends the state itself), so the
        // state is waited for before it is read: the answer alone does not say the observer has run.
        #expect(
            await rig.pumpHost(until: { session.side.states.last?.selection == Neon.id && session.side.states.last?.outcome == .prepared }),
            "the choice is published as a state")
        let state = try #require(session.side.states.last)
        #expect(state.selection == Neon.id)
        #expect(state.outcome == .prepared)
        #expect(session.side.store.values.values.first == "package:neon", "the choice is remembered")
        #expect(session.side.store.writes.count == 1)

        let camera = await session.capture()
        #expect(
            Self.compiledEffects(of: rig) == ["bundled", "neon first"], "drawing the frame compiled nothing more: the package's library was kept")
        let drawn = try session.lastPass()
        #expect(Self.effect(of: drawn.kernel) == "neon first", "the frame was drawn with the package's library")
        #expect(ObjectIdentifier(drawn.input) == ObjectIdentifier(camera), "...from the camera's frame")
        #expect(session.streamed.map(ObjectIdentifier.init) == [ObjectIdentifier(drawn.output)], "the extension streams that pass's output")
        #expect(rig.host.pipeline.stats.effectsApplied == 1)
        #expect(rig.host.pipeline.stats.effectFailures.isEmpty)

        try await session.finish()
        #expect(rig.host.errors.entries.count == 0)
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.ext.pool.liveCount == 0)
    }

    // MARK: 3. Rewriting the source prepares it again

    @Test("rewriting the chosen package's source in place compiles it again and the next frame is drawn with the new library")
    func aRewrittenSourceIsPreparedAgain() async throws {
        let session = try await Session.start()
        let rig = session.rig
        #expect(await session.install(source: Neon.first))
        #expect(await rig.choose(Neon.id) == .prepared)
        _ = await session.capture()
        #expect(Self.compiledEffects(of: rig) == ["bundled", "neon first"], "the first frame compiled nothing more")
        let firstKernel = try session.lastPass().kernel
        #expect(Self.effect(of: firstKernel) == "neon first")

        // An in-place save: the file is overwritten, so only the file's own watch hears it.
        session.side.fileSystem.write(Neon.sourcePath, Neon.second)
        await rig.editFolder(firing: Neon.sourcePath)
        #expect(await session.waitForCompiles(of: "Neon", count: 2), "the edit prepared the package again")

        #expect(Self.compiledEffects(of: rig) == ["bundled", "neon first", "neon second"])
        _ = await session.capture()
        #expect(Self.compiledEffects(of: rig) == ["bundled", "neon first", "neon second"], "the second frame compiled nothing more")
        let secondKernel = try session.lastPass().kernel
        #expect(Self.effect(of: secondKernel) == "neon second", "the next frame is drawn with the rewritten source")
        #expect(ObjectIdentifier(secondKernel) != ObjectIdentifier(firstKernel), "...a new library, not the one the first frame used")
        #expect(session.streamed.count == 2)
        #expect(rig.host.pipeline.stats.effectsApplied == 2)

        try await session.finish()
        #expect(rig.host.errors.entries.count == 0)
        #expect(rig.host.textures.isBalanced)
    }

    // MARK: 4. A source that does not compile costs the effect, not the picture

    @Test("a source that does not compile passes the camera's frame through, and fixing it brings the effect back")
    func aBrokenSourceIsPassedThroughUntilItIsFixed() async throws {
        let session = try await Session.start()
        let rig = session.rig
        #expect(await session.install(source: Neon.first))
        #expect(await rig.choose(Neon.id) == .prepared)
        _ = await session.capture()
        let submitted = rig.host.gpu.submissions.count

        // An atomic save: the editor writes the file anew, which only the package directory's watch hears.
        rig.host.shaders.failCompile(
            of: Self.assembled(Neon.broken), with: ShaderDiagnostics(message: "effect:2:25: error: use of undeclared identifier 'oops'", code: 3))
        session.side.fileSystem.remove(Neon.sourcePath)
        session.side.fileSystem.write(Neon.sourcePath, Neon.broken)
        await rig.editFolder(firing: Neon.directory)
        let failed = await rig.pumpHost(until: { session.side.states.last?.outcome == .failed(.compileFailed) })
        #expect(failed, "the menu shows that the chosen effect did not compile")
        #expect(session.side.states.last?.selection == Neon.id, "...and the choice stands")

        let camera = await session.capture()
        #expect(session.streamed.last.map(ObjectIdentifier.init) == ObjectIdentifier(camera), "the extension got the camera's own frame")
        #expect(rig.host.gpu.submissions.count == submitted, "no pass was committed")
        #expect(rig.host.pipeline.stats.effectFailures == [.compileFailed: 1])
        #expect(rig.host.pipeline.stats.framesDropped == 0, "a broken effect drops nothing")
        let errors = rig.host.errors.messages(in: .effect)
        #expect(errors.count == 1, "the failure is reported once")
        #expect(errors.first?.contains("use of undeclared identifier 'oops'") == true)

        // Fixing the file prepares it again, and the frames are drawn with the effect.
        let published = session.side.states.count
        session.side.fileSystem.write(Neon.sourcePath, Neon.first)
        await rig.editFolder(firing: Neon.sourcePath)
        #expect(await rig.pumpHost(until: { session.side.states.count > published && session.side.states.last?.outcome == .prepared }))

        let fixed = await session.capture()
        let drawn = try session.lastPass()
        #expect(Self.effect(of: drawn.kernel) == "neon first", "the effect is back")
        #expect(ObjectIdentifier(drawn.input) == ObjectIdentifier(fixed))
        #expect(session.streamed.last.map(ObjectIdentifier.init) == ObjectIdentifier(drawn.output))
        #expect(rig.host.gpu.submissions.count == submitted + 1)

        try await session.finish()
        #expect(rig.host.textures.isBalanced)
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.ext.pool.liveCount == 0)
    }

    // MARK: 5. Removing the package falls back to the bundled effect

    @Test("removing the chosen package falls back to the bundled effect, and the choice is not forgotten")
    func aRemovedPackageFallsBackToTheBundledEffect() async throws {
        let session = try await Session.start()
        let rig = session.rig
        #expect(await session.install(source: Neon.first))
        #expect(await rig.choose(Neon.id) == .prepared)
        _ = await session.capture()
        #expect(Self.compiledEffects(of: rig) == ["bundled", "neon first"])

        session.side.fileSystem.remove(Neon.directory)
        await rig.editFolder(firing: CatalogSide.folder)
        let fellBack = await rig.pumpHost(until: { session.side.states.last?.entries.map(\.id) == [Self.bundledID] })
        #expect(fellBack, "the package is gone from the catalog")
        let state = try #require(session.side.states.last)
        #expect(state.selection == Self.bundledID)
        #expect(state.outcome == .prepared)
        #expect(rig.host.developer.contains("effect 'Neon' is gone; back to 'Chromatic Grain'"))
        #expect(session.side.store.values.values.first == "package:neon", "only a choice is remembered: the package comes back with its folder")
        #expect(session.side.store.writes.count == 1)

        let camera = await session.capture()
        let drawn = try session.lastPass()
        #expect(Self.effect(of: drawn.kernel) == "bundled", "the frame is drawn with the bundled effect")
        #expect(ObjectIdentifier(drawn.input) == ObjectIdentifier(camera))
        #expect(session.streamed.last.map(ObjectIdentifier.init) == ObjectIdentifier(drawn.output))
        #expect(Self.compiledEffects(of: rig) == ["bundled", "neon first"], "the bundled library was kept, not compiled again")

        try await session.finish()
        #expect(rig.host.errors.entries.count == 0)
        #expect(rig.host.textures.isBalanced)
    }

    // MARK: 6. A thumbnail edited in place reaches the catalog, and costs no compile

    @Test("a package's thumbnail is in its entry, and rewriting the file in place lists the new picture without compiling anything")
    func anEditedThumbnailReachesTheCatalog() async throws {
        let session = try await Session.start()
        let side = session.side
        let first = EffectThumbnail.fixture(1)
        let second = EffectThumbnail.fixture(2, format: .jpeg)
        side.fileSystem.write(Neon.manifestPath, Neon.manifestWithThumbnail)
        side.fileSystem.write(Neon.sourcePath, Neon.first)
        side.fileSystem.write(Neon.thumbnailPath, bytes: first.data)
        await session.rig.editFolder(firing: CatalogSide.folder)
        #expect(await session.rig.pumpHost(until: { side.states.last?.entries.last?.thumbnail == first }), "the package is listed with its picture")

        // An in-place save: only the thumbnail file's own watch hears it, so this also proves that it is watched.
        side.fileSystem.write(Neon.thumbnailPath, bytes: second.data)
        await session.rig.editFolder(firing: Neon.thumbnailPath)
        #expect(await session.rig.pumpHost(until: { side.states.last?.entries.last?.thumbnail == second }), "the new picture is listed")

        let entry = try #require(side.states.last?.entries.last)
        #expect(entry.id == Neon.id)
        #expect(entry.availability == .ready)
        #expect(side.states.last?.selection == Self.bundledID, "listing a picture chooses nothing")
        #expect(Self.compiledEffects(of: session.rig) == ["bundled"], "and compiles nothing")

        try await session.finish()
        #expect(session.rig.host.errors.entries.count == 0)
    }
}

// MARK: - Fixtures and helpers

extension EffectCatalogIntegrationTests {
    private static let bundledID = EffectID.bundled(ChromaticGrainEffect.name)

    /// What the compiler is handed for an author's `source`: the prelude, the line directive and the source.
    /// The fake gateway does not read it: it mints a library per source and remembers it, so the text is the
    /// library's identity.
    private static func assembled(_ source: String) -> String {
        ShaderSourceAssembly.assemble(source)
    }

    /// Which effect a compiled source is, by a name a failure can print (the sources are prelude-long).
    private static let effectNames: [String: String] = [
        assembled(BundledEffectDataSourceImpl().defaultEffect.source): "bundled",
        assembled(Neon.first): "neon first",
        assembled(Neon.second): "neon second",
        assembled(Neon.broken): "neon broken",
    ]

    private static func effect(of library: FakeLibraryHandle) -> String {
        effectNames[library.source] ?? "something else"
    }

    /// The effects the fake compiler has been asked for, in order.
    private static func compiledEffects(of rig: LoopbackRig) -> [String] {
        rig.host.shaders.calls.values.map { effectNames[$0.source] ?? "something else" }
    }

    /// The package the tests drop into the effects folder.
    private enum Neon {
        static let id = EffectID.package("neon")
        static let directory = "\(CatalogSide.folder)/neon.lens"
        static let manifestPath = "\(directory)/manifest.json"
        static let sourcePath = "\(directory)/effect.metal"
        static let manifest = #"{"formatVersion": 1, "name": "Neon", "author": "Example Author"}"#
        static let thumbnailPath = "\(directory)/thumbnail.png"
        static let manifestWithThumbnail = #"{"formatVersion": 1, "name": "Neon", "author": "Example Author", "thumbnail": "thumbnail.png"}"#
        static let first = "// Neon, first version\nkernel void effect() {}"
        static let second = "// Neon, second version\nkernel void effect() {}"
        static let broken = "// Neon, with a typo\nkernel void effect() { oops }"

        static func write(into fileSystem: InMemoryFileSystemGateway, source: String) {
            fileSystem.write(manifestPath, manifest)
            fileSystem.write(sourcePath, source)
        }
    }

    /// One pass as the fake GPU recorded it: the library it ran and the two surfaces it bound.
    private struct Pass {
        let kernel: FakeLibraryHandle
        let input: FakeSurfaceHandle
        let output: FakeSurfaceHandle
    }

    /// The loopback with the extension up, the host started and the catalog running on the bundled effect.
    private final class Session {
        let rig: LoopbackRig
        let side: CatalogSide
        private let relay: Task<Void, any Error>
        private let running: CatalogRun
        private var cameraFrames = 0

        private init(rig: LoopbackRig, side: CatalogSide, relay: Task<Void, any Error>, running: CatalogRun) {
            self.rig = rig
            self.side = side
            self.relay = relay
            self.running = running
        }

        @MainActor
        static func start() async throws -> Session {
            let rig = LoopbackRig(effects: .real, catalog: .real)
            let side = try #require(rig.host.catalog)
            let relay = await rig.startExtension()
            try await rig.startHost()
            let running = try #require(await rig.startCatalog())
            return Session(rig: rig, side: side, relay: relay, running: running)
        }

        /// Ends the catalog's run, the extension and the host; every file watch the catalog armed is stopped
        /// (once each) and the fake GPU has no pass or draw pending.
        @MainActor
        func finish() async throws {
            await rig.stopCatalog(running)
            // The catalog arms its watches again on every listing, and the end of a watch's stream stops them.
            // That may land a moment after the run ends, so this waits for the positive condition.
            #expect(await rig.pumpHost(until: { side.fileWatch.isBalanced }), "a file watch the catalog armed was not stopped, or was stopped twice")
            try await rig.stopExtension(relay)
            rig.stopHostExpectingIdleGPU()
        }

        /// Writes the Neon package into the folder and returns once the catalog lists it.
        @MainActor
        func install(source: String) async -> Bool {
            Neon.write(into: side.fileSystem, source: source)
            await rig.editFolder(firing: CatalogSide.folder)
            return await rig.pumpHost(until: { side.states.contains { $0.entries.contains { $0.id == Neon.id } } })
        }

        /// Returns once the effect named `name` has compiled `count` times (the runtime logs each).
        @MainActor
        func waitForCompiles(of name: String, count: Int) async -> Bool {
            let line = "effect '\(name)' compiled"
            let developer = rig.host.developer
            return await rig.pumpHost(until: { developer.messages(in: .effect).filter { $0 == line }.count >= count })
        }

        /// One camera frame through the runtime, and the extension has received it.
        @MainActor
        func capture() async -> FakeSurfaceHandle {
            cameraFrames += 1
            let camera = FakeSurfaceHandle(id: UInt32(cameraFrames))
            await rig.captureThroughRuntime(camera, at: UInt64(cameraFrames) * 1_000)
            await rig.pumpExtension(untilReceived: cameraFrames)
            return camera
        }

        /// The surfaces the extension has streamed, in arrival order.
        var streamed: [FakeSurfaceHandle] {
            rig.ext.stream.sent.values.compactMap { $0.surface as? FakeSurfaceHandle }
        }

        /// The newest pass the fake GPU committed: texture 0 is the input, the last texture the output.
        func lastPass() throws -> Pass {
            let pass = try #require(rig.host.gpu.submissions.values.last?.pass, "no pass was committed")
            let textures = try #require(pass.textures as? [FakeTextureHandle], "the pass bound the fake gateway's textures")
            #expect(textures.count == 2, "an effect pass binds its input and its output")
            return Pass(
                kernel: try #require(pass.kernel as? FakeLibraryHandle),
                input: try #require(textures.first).surface,
                output: try #require(textures.last).surface)
        }
    }
}
