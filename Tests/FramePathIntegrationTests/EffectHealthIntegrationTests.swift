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
