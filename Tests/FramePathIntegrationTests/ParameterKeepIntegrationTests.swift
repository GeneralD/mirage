import Domain
import TestDoubles
import TestSupport
import Testing

/// What a parameter keeps across the catalog's runs on the loopback (`docs/hackathon/mvp-cd/specs/parameters.md`,
/// Persistence): a written value is stored once its quiet period has run out, a run that stops stores what still waits,
/// a stored value is what a choice of its effect starts from, and a stored value that does not decode is ignored and kept
/// as it is. Each test is one spec sentence, judged on the catalog's store (`rig.host.catalog?.store`), on the states the
/// catalog published and on the block of the pass the fake GPU committed.
///
/// Nothing here sleeps or reads a clock: the quiet period runs out when the test advances the catalog's `GatedClock` after
/// the sleep is parked, and a store or a state is waited for by what it shows, never by time.
@MainActor
@Suite("Parameter persistence through the loopback", .timeLimit(.minutes(1)))
struct ParameterKeepIntegrationTests {
    /// The key `Tuner`'s values are stored under (`docs/hackathon/mvp-cd/specs/parameters.md`, Persistence).
    private static let key = "effect.parameters.v1.package:tuner"

    /// `Tuner` with `mode` removed and `strength` narrowed to 0...0.5: the edit the reconcile test makes to the manifest.
    private static let narrowedManifest =
        #"{"formatVersion": 1, "name": "Tuner", "parameters": [{"id": "strength", "label": "Strength", "type": "float", "min": 0, "max": 0.5, "default": 0.5}]}"#

    @Test("a value set to a parameter is stored 500 ms later, and not before")
    func aSetValueIsStoredAfterTheQuietPeriod() async throws {
        let session = try await ParameterSession.start()
        let side = session.side
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)

        let parked = side.clock.sleepers.count
        await session.set("strength", to: .float(0.75))
        #expect(
            await session.rig.pumpHost(until: { Self.value(of: "strength", in: side.states.last) == .float(0.75) }),
            "the panel's state shows 0.75")
        await side.clock.sleepers.waitForCount(parked + 1)

        side.clock.advance(by: .milliseconds(499))
        #expect(side.store.values[Self.key] == nil, "nothing is stored at 499 ms")

        side.clock.advance(by: .milliseconds(1))
        #expect(await session.rig.pumpHost(until: { side.store.values[Self.key] != nil }), "the value is stored at 500 ms")
        try await session.finish()
    }

    @Test("a catalog started again restores the stored value: the state it publishes and the next pass carry 0.75")
    func aRestartedCatalogRestoresTheStoredValue() async throws {
        let session = try await RunningSession.start()
        let side = session.side
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)

        let parked = side.clock.sleepers.count
        await session.set("strength", to: .float(0.75))
        #expect(
            await session.rig.pumpHost(until: { Self.value(of: "strength", in: side.states.last) == .float(0.75) }),
            "the panel's state shows 0.75")
        await side.clock.sleepers.waitForCount(parked + 1)
        side.clock.advance(by: .milliseconds(500))
        #expect(await session.rig.pumpHost(until: { side.store.values[Self.key] != nil }), "the value is stored at 500 ms")

        // `startCatalog()` returns on the states the collector already holds, so the restart is waited for by a new state.
        let statesBefore = side.states.count
        #expect(await session.restart(), "the catalog was started again")
        #expect(
            await session.rig.pumpHost(until: {
                side.states.count > statesBefore && Self.value(of: "strength", in: side.states.last) == .float(0.75)
            }),
            "the state the restarted catalog publishes shows 0.75")
        await session.drawFrame()

        let pass = try session.lastPass()
        #expect(Array(pass.parameters.bytes.prefix(4)) == [0x00, 0x00, 0x40, 0x3F], "the next pass starts with 0.75")
        try await session.finish()
    }

    @Test("a value still waiting for its quiet period is stored at once when the catalog stops")
    func aWaitingValueIsStoredWhenTheCatalogStops() async throws {
        let session = try await ParameterSession.start()
        let side = session.side
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)

        await session.set("strength", to: .float(0.75))
        #expect(
            await session.rig.pumpHost(until: { Self.value(of: "strength", in: side.states.last) == .float(0.75) }),
            "the panel's state shows 0.75")
        #expect(side.store.values[Self.key] == nil, "the write waits for its quiet period, and the clock has not moved")

        try await session.finish()
        #expect(side.store.values[Self.key] != nil, "the run that stopped stored the value before the quiet period ran out")
    }

    @Test("a changed manifest reconciles the stored value: the removed parameter is dropped, the value is clamped, the store is not written")
    func aChangedManifestReconcilesTheValue() async throws {
        let session = try await ParameterSession.start()
        let side = session.side
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)

        let parked = side.clock.sleepers.count
        await session.set("strength", to: .float(0.75))
        #expect(
            await session.rig.pumpHost(until: { Self.value(of: "strength", in: side.states.last) == .float(0.75) }),
            "the panel's state shows 0.75")
        await side.clock.sleepers.waitForCount(parked + 1)
        side.clock.advance(by: .milliseconds(500))
        #expect(await session.rig.pumpHost(until: { side.store.values[Self.key] != nil }), "the value is stored at 500 ms")
        let stored = side.store.values[Self.key]
        let writesBefore = side.store.writes.count

        side.fileSystem.write(Tuner.manifestPath, Self.narrowedManifest)
        await session.rig.editFolder(firing: Tuner.manifestPath)
        #expect(
            await session.rig.pumpHost(until: {
                Self.parameterIDs(in: side.states.last) == ["strength"] && Self.value(of: "strength", in: side.states.last) == .float(0.5)
            }),
            "the panel lists strength alone, at 0.5: the 0.75 in memory is clamped")
        await session.drawFrame()

        let pass = try session.lastPass()
        #expect(Array(pass.parameters.bytes.prefix(4)) == [0x00, 0x00, 0x00, 0x3F], "the next pass starts with 0.5")
        #expect(side.store.values[Self.key] == stored, "the reconcile leaves the stored value as it is")
        #expect(side.store.writes.count == writesBefore, "the reconcile writes nothing to the store")
        try await session.finish()
    }

    @Test("a stored value that does not decode is ignored, with one developer line, and the stored string is kept as it is")
    func aStoredValueThatDoesNotDecodeIsIgnored() async throws {
        let session = try await ParameterSession.start()
        let side = session.side
        #expect(await session.install())
        side.store.set("garbage", forKey: Self.key)

        #expect(await session.rig.choose(Tuner.id) == .prepared)
        await session.drawFrame()

        let pass = try session.lastPass()
        #expect(pass.parameters.bytes == Tuner.block(strength: Tuner.halfStrength, mode: Tuner.softMode), "the choice starts from the defaults")
        let lines = session.rig.host.developer.messages(in: .effect).filter { $0.hasPrefix("stored parameter values") }
        #expect(lines == ["stored parameter values of 'package:tuner' do not decode, ignored: garbage"], "one developer line names the value")
        #expect(side.store.values[Self.key] == "garbage", "the stored string is kept as it is")
        try await session.finish()
    }

    /// The value the state shows for the parameter `id`, or nil when the state lists no such parameter.
    private static func value(of id: String, in state: EffectCatalogState?) -> EffectParameterValue? {
        state?.parameters.first(where: { $0.spec.id == id })?.value
    }

    /// The ids of the parameters the state lists, in order.
    private static func parameterIDs(in state: EffectCatalogState?) -> [String] {
        state?.parameters.map { $0.spec.id } ?? []
    }
}

/// `ParameterSession` keeps its catalog run private, and a restart has to end that run before it starts another, so the
/// restart test holds the run itself. Its start, drawing and finish are those of `ParameterSession`, and the run's own work
/// is `LoopbackRig.startCatalog()` and `stopCatalog(_:)` (`LoopbackCatalog.swift`).
@MainActor
private final class RunningSession {
    let rig: LoopbackRig
    let side: CatalogSide
    private let relay: Task<Void, any Error>
    private var running: CatalogRun
    private var cameraFrames = 0

    private init(rig: LoopbackRig, side: CatalogSide, relay: Task<Void, any Error>, running: CatalogRun) {
        self.rig = rig
        self.side = side
        self.relay = relay
        self.running = running
    }

    static func start() async throws -> RunningSession {
        let rig = LoopbackRig(effects: .real, catalog: .real)
        let side = try #require(rig.host.catalog)
        let relay = await rig.startExtension()
        try await rig.startHost()
        let running = try #require(await rig.startCatalog())
        return RunningSession(rig: rig, side: side, relay: relay, running: running)
    }

    /// Ends the run and starts another on the same rig, which begins from what the settings hold.
    func restart() async -> Bool {
        await rig.stopCatalog(running)
        guard let next = await rig.startCatalog() else { return false }
        running = next
        return true
    }

    /// Ends the catalog's run, the extension and the host, and checks that the GPU has nothing pending.
    func finish() async throws {
        await rig.stopCatalog(running)
        #expect(await rig.pumpHost(until: { side.fileWatch.isBalanced }), "a file watch the catalog armed was not stopped, or was stopped twice")
        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    /// Writes `Tuner` into the folder and returns once the catalog lists it.
    func install() async -> Bool {
        Tuner.write(into: side.fileSystem)
        await rig.editFolder(firing: CatalogSide.folder)
        return await rig.pumpHost(until: { side.states.contains { $0.entries.contains { $0.id == Tuner.id } } })
    }

    /// Sets the parameter `id` of the chosen effect through the catalog's UseCase, as the panel does.
    func set(_ id: String, to value: EffectParameterValue) async {
        guard let useCase = rig.host.catalog?.useCase else {
            Issue.record("set needs a host built with catalog: .real")
            return
        }
        await useCase.setParameter(id, to: value)
    }

    /// One camera frame through the runtime, and the extension has received it.
    func drawFrame() async {
        cameraFrames += 1
        let camera = FakeSurfaceHandle(id: UInt32(cameraFrames))
        await rig.captureThroughRuntime(camera, at: UInt64(cameraFrames) * 1_000)
        await rig.pumpExtension(untilReceived: cameraFrames)
    }

    /// The newest pass the fake GPU committed.
    func lastPass() throws -> ComputePass {
        try #require(rig.host.gpu.submissions.values.map(\.pass).last, "no pass was committed")
    }
}
