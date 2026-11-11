import BundledEffectDataSource
import Domain
import Foundation
import ShaderCompilationDataSource
import TestDoubles
import TestSupport
import Testing

/// The effect health policy on the loopback (epic #42, E4 health, #145): the real catalog and the real
/// effect runtime (`LoopbackRig(effects: .real, catalog: .real)`), with only the OS boundary and the GPU
/// faked. A chosen package whose command buffers time out is switched off after five failures in a row
/// (#122), every frame still reaches the extension, and the frame after the switch-off is drawn with the
/// bundled effect.
///
/// Nothing here sleeps or reads a clock: the GPU completes each command buffer by hand, and the catalog
/// and the runtime are pumped until the state that a failure causes is published.
///
/// The helpers that `EffectCatalogIntegrationTests` keeps private are copied here, so that file stays as it is.
@MainActor
@Suite("Effect health on the loopback", .timeLimit(.minutes(1)))
struct EffectHealthIntegrationTests {
    // MARK: 1. Five timeouts in a row still deliver every frame to the extension

    @Test("a package whose command buffers time out five times in a row still delivers all five frames to the extension")
    func fiveTimeoutsInARowStillDeliverEveryFrame() async throws {
        let session = try await Session.start()
        let rig = session.rig
        let side = session.side
        #expect(await session.install(source: Neon.first))
        #expect(await rig.choose(Neon.id) == .prepared)

        var cameras: [FakeSurfaceHandle] = []
        for _ in 0..<5 {
            cameras.append(await session.capture(completing: .failed(code: 2)))
        }

        let stats = rig.host.pipeline.stats
        #expect(stats.effectFailures == [.timeout: 5])
        #expect(stats.framesReceived == 5)
        #expect(stats.framesSent == 5)
        #expect(stats.framesDropped == 0)
        #expect(stats.framesSent + stats.framesDropped == stats.framesReceived)
        #expect(
            session.streamed.map(ObjectIdentifier.init) == cameras.map(ObjectIdentifier.init),
            "each timed-out frame reached the extension as the camera's own surface")
        #expect(Self.passedEffects(of: rig) == Array(repeating: "neon first", count: 5), "all five passes ran the package's library")
        #expect(Self.compiledEffects(of: rig) == ["bundled", "neon first"], "the package was compiled once, and nothing else was")

        // The fifth timeout switches the package off; the catalog publishes that after the bundled effect is prepared.
        #expect(await rig.pumpHost(until: { side.states.contains { $0.disabled[Neon.id] != nil } }))
        try await session.finish()
    }

    // MARK: 2. After the fifth timeout the next frame is drawn with the bundled effect

    @Test("after the fifth timeout the package is switched off and the next frame is drawn with the bundled effect")
    func theFrameAfterTheFifthTimeoutIsDrawnWithTheBundledEffect() async throws {
        let session = try await Session.start()
        let rig = session.rig
        let side = session.side
        #expect(await session.install(source: Neon.first))
        #expect(await rig.choose(Neon.id) == .prepared)
        for _ in 0..<5 {
            _ = await session.capture(completing: .failed(code: 2))
        }

        // The switch-off goes outcome → session → store → the bundled effect's prepare, on other tasks, so the state that
        // carries it is waited for before it is read.
        #expect(await rig.pumpHost(until: { side.states.contains { $0.disabled[Neon.id] != nil } }), "the package is switched off")
        let state = try #require(side.states.last)
        #expect(state.selection == Neon.id, "the choice stands")
        #expect(state.disabled[Neon.id] == .failure(.timeout))
        #expect(side.store.values["selectedEffect"] == "package:neon", "the choice is remembered")
        #expect(side.store.values["disabledEffects.v1"]?.contains("timeout") == true, "the switch-off is remembered")
        #expect(rig.host.errors.messages(in: .effect) == ["effect 'Neon' disabled (timeout); back to 'Chromatic Grain'"])

        let sixth = await session.capture()
        let drawn = try session.lastPass()
        #expect(
            drawn.kernel.source == Self.assembled(BundledEffectDataSourceImpl().defaultEffect.source),
            "the sixth frame is drawn with the bundled effect")
        #expect(ObjectIdentifier(drawn.input) == ObjectIdentifier(sixth), "...from the camera's frame")
        #expect(session.streamed.last.map(ObjectIdentifier.init) == ObjectIdentifier(drawn.output), "the extension streams that pass's output")
        #expect(Self.passedEffects(of: rig).filter { $0 == "neon first" }.count == 5, "no pass of the package ran after the switch-off")
        #expect(rig.host.pipeline.stats.effectsApplied == 1)
        #expect(rig.host.pipeline.stats.effectFailures == [.timeout: 5])

        try await session.finish()
        #expect(rig.host.textures.isBalanced)
    }

    // MARK: 3. A success resets the count, so four timeouts either side of it do not switch the package off

    @Test("four timeouts, a success and four more timeouts do not switch the package off, and access revoked does at once")
    func aSuccessResetsTheTimeoutCount() async throws {
        let session = try await Session.start()
        let rig = session.rig
        let side = session.side
        #expect(await session.install(source: Neon.first))
        #expect(await rig.choose(Neon.id) == .prepared)

        for _ in 0..<4 {
            _ = await session.capture(completing: .failed(code: 2))
        }
        _ = await session.capture()
        for _ in 0..<4 {
            _ = await session.capture(completing: .failed(code: 2))
        }

        #expect(rig.host.pipeline.stats.effectFailures == [.timeout: 8])
        #expect(rig.host.pipeline.stats.effectsApplied == 1)
        #expect(Self.passedEffects(of: rig) == Array(repeating: "neon first", count: 9), "all nine passes ran the package's library")
        #expect(side.states.last?.disabled[Neon.id] == nil, "the package is still on after nine passes")
        #expect(side.states.last?.selection == Neon.id)

        // The sentinel: one access-revoked failure switches the package off at once, which shows the switch-off is wired.
        _ = await session.capture(completing: .failed(code: 4))
        #expect(
            await rig.pumpHost(until: { side.states.last?.disabled[Neon.id] == .failure(.accessRevoked) }),
            "the tenth pass's access-revoked failure switches the package off")
        #expect(Self.passedEffects(of: rig) == Array(repeating: "neon first", count: 10), "the tenth pass was the package's too")
        #expect(rig.host.pipeline.stats.effectFailures == [.timeout: 8, .accessRevoked: 1])
        #expect(rig.host.errors.messages(in: .effect) == ["effect 'Neon' disabled (accessRevoked); back to 'Chromatic Grain'"])

        try await session.finish()
    }

    // MARK: 4. A switch-off survives a restart, and the first frame after it is drawn with the bundled effect

    @Test("a switch-off survives a restart: the relaunched catalog keeps the package off and draws its first frame with the bundled effect")
    func aSwitchOffSurvivesARestart() async throws {
        let first = try await Session.start()
        #expect(await first.install(source: Neon.first))
        #expect(await first.rig.choose(Neon.id) == .prepared)
        for _ in 0..<5 {
            _ = await first.capture(completing: .failed(code: 2))
        }
        #expect(await first.rig.pumpHost(until: { first.side.states.contains { $0.disabled[Neon.id] != nil } }), "the package is switched off")
        // The relaunch is given what the first run kept in the defaults, and a new folder on disk, so the package is written again.
        let store = first.side.store
        let writesBefore = store.writes.count
        try await first.finish()

        let second = try await Session.start(store: store, installing: Neon.first)
        let rig = second.rig
        let firstState = try #require(second.side.states.values.first)
        #expect(firstState.selection == Neon.id, "the choice stands")
        #expect(firstState.disabled == [Neon.id: .failure(.timeout)], "the switch-off stands")
        #expect(firstState.outcome == nil, "no answer is shown for the choice, which is switched off")
        #expect(await rig.pumpHost(until: { second.side.states.last?.outcome == .prepared }), "the bundled effect is prepared in its place")
        #expect(
            rig.host.shaders.calls.values.map(\.source) == [Self.assembled(BundledEffectDataSourceImpl().defaultEffect.source)],
            "the relaunch compiled the bundled effect and nothing else")

        _ = await second.capture()
        let drawn = try second.lastPass()
        #expect(
            drawn.kernel.source == Self.assembled(BundledEffectDataSourceImpl().defaultEffect.source),
            "the first frame after the relaunch is drawn with the bundled effect")
        #expect(store.writes.count == writesBefore, "the relaunch wrote nothing: the switch-off was only read back")

        try await second.finish()
    }

    // MARK: 5. Rewriting a switched-off package's source lifts the switch-off and draws the next frame with it

    @Test("rewriting a switched-off package's source lifts the switch-off, and the next frame is drawn with the rewritten source")
    func aRewrittenSourceLiftsTheSwitchOff() async throws {
        let session = try await Session.start()
        let rig = session.rig
        let side = session.side
        #expect(await session.install(source: Neon.first))
        #expect(await rig.choose(Neon.id) == .prepared)
        for _ in 0..<5 {
            _ = await session.capture(completing: .failed(code: 2))
        }
        #expect(await rig.pumpHost(until: { side.states.contains { $0.disabled[Neon.id] != nil } }), "the package is switched off")

        #expect(await session.install(source: Neon.second), "the rewritten package is listed")
        #expect(await session.waitForCompiles(of: "Neon", count: 2), "the rewritten source was compiled")
        #expect(
            await rig.pumpHost(until: { side.states.last?.disabled.isEmpty == true && side.states.last?.outcome == .prepared }),
            "the switch-off is lifted and the rewritten source is prepared")
        #expect(side.store.values["disabledEffects.v1"] == "[]", "the lifted switch-off is forgotten")

        _ = await session.capture()
        let drawn = try session.lastPass()
        #expect(drawn.kernel.source == Self.assembled(Neon.second), "the next frame is drawn with the rewritten source")
        #expect(Self.compiledEffects(of: rig) == ["bundled", "neon first", "neon second"], "the rewritten source was the only compile added")

        try await session.finish()
    }

    // MARK: 6. Re-enabling forgets the switch-off and runs the same source again

    @Test("re-enabling a switched-off package forgets the switch-off and draws the next frame with the same source, compiling nothing new")
    func reenablingForgetsTheSwitchOffAndRunsTheSameSource() async throws {
        let session = try await Session.start()
        let rig = session.rig
        let side = session.side
        #expect(await session.install(source: Neon.first))
        #expect(await rig.choose(Neon.id) == .prepared)
        for _ in 0..<5 {
            _ = await session.capture(completing: .failed(code: 2))
        }
        #expect(await rig.pumpHost(until: { side.states.contains { $0.disabled[Neon.id] != nil } }), "the package is switched off")
        let compiled = rig.host.shaders.calls.count

        #expect(await rig.reenable(Neon.id) == .prepared, "the package is chosen again")
        #expect(
            await rig.pumpHost(until: { side.states.last?.disabled.isEmpty == true && side.states.last?.outcome == .prepared }),
            "the switch-off is forgotten")
        #expect(side.store.values["disabledEffects.v1"] == "[]", "the forgetting is remembered")
        #expect(rig.host.shaders.calls.count == compiled, "the same source was run again, not compiled again")

        _ = await session.capture()
        let drawn = try session.lastPass()
        #expect(Self.effect(of: drawn.kernel) == "neon first", "the next frame is drawn with the package again")
        #expect(rig.host.shaders.calls.count == compiled, "the second frame compiled nothing either")

        try await session.finish()
    }

    // MARK: 7. The bundled effect is never switched off: a GPU that keeps failing is reported, and nothing is remembered

    @Test("five bundled failures in a row report the GPU as unavailable and switch nothing off, and one good pass clears it")
    func theBundledEffectIsNeverSwitchedOff() async throws {
        let session = try await Session.start()
        let rig = session.rig
        let side = session.side
        for _ in 0..<5 {
            _ = await session.capture(completing: .failed(code: 2))
        }
        #expect(rig.host.pipeline.stats.framesSent == 5, "all five frames reached the extension")
        #expect(session.streamed.count == 5)
        #expect(
            await rig.pumpHost(until: { side.states.contains { $0.isGPUUnavailable && $0.disabled.isEmpty } }),
            "the menu says the GPU is unavailable, and no effect is switched off")
        #expect(side.store.values["disabledEffects.v1"] == nil, "nothing is remembered")

        _ = await session.capture()
        #expect(await rig.pumpHost(until: { side.states.last?.isGPUUnavailable == false }), "one good pass clears the GPU warning")

        try await session.finish()
    }
}

// MARK: - Fixtures and helpers

extension EffectHealthIntegrationTests {
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
    ]

    private static func effect(of library: FakeLibraryHandle) -> String {
        effectNames[library.source] ?? "something else"
    }

    /// The effects the fake compiler has been asked for, in order.
    private static func compiledEffects(of rig: LoopbackRig) -> [String] {
        rig.host.shaders.calls.values.map { effectNames[$0.source] ?? "something else" }
    }

    /// The effect each committed pass ran, in commit order.
    private static func passedEffects(of rig: LoopbackRig) -> [String] {
        rig.host.gpu.submissions.values.compactMap { $0.pass.kernel as? FakeLibraryHandle }.map { effect(of: $0) }
    }

    /// The package the tests drop into the effects folder.
    private enum Neon {
        static let id = EffectID.package("neon")
        static let directory = "\(CatalogSide.folder)/neon.lens"
        static let manifestPath = "\(directory)/manifest.json"
        static let sourcePath = "\(directory)/effect.metal"
        static let manifest = #"{"formatVersion": 1, "name": "Neon", "author": "Example Author", "description": "Tubes that hum"}"#
        static let first = "// Neon, first version\nkernel void effect() {}"
        static let second = "// Neon, second version\nkernel void effect() {}"

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

        /// Starts the loopback with `store` as the defaults the run keeps its choice and its switch-offs in. With `source`,
        /// the package is written into the folder before the catalog lists it, as a relaunch finds it on disk.
        @MainActor
        static func start(store: InMemoryKeyValueStore = InMemoryKeyValueStore(), installing source: String? = nil) async throws -> Session {
            let rig = LoopbackRig(effects: .real, catalog: .real, catalogStore: store)
            let side = try #require(rig.host.catalog)
            let relay = await rig.startExtension()
            try await rig.startHost()
            if let source {
                Neon.write(into: side.fileSystem, source: source)
            }
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

        /// One camera frame through the runtime, completed with `completion` (what the device reports for its command
        /// buffer), and the extension has received it.
        @MainActor
        func capture(completing completion: GPUCompletion = .finished) async -> FakeSurfaceHandle {
            cameraFrames += 1
            let camera = FakeSurfaceHandle(id: UInt32(cameraFrames))
            await rig.captureThroughRuntime(camera, at: UInt64(cameraFrames) * 1_000, completing: completion)
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
