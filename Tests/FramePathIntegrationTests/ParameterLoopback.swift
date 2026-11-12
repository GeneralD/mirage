import Domain
import TestDoubles
import TestSupport
import Testing

/// The package the parameter tests drop into the effects folder: a float `strength` and a `mode` choice, which the
/// layout places at offsets 0 and 4 with stride 8, so the block is the 8 bytes of the two fields padded to the
/// block's 16-byte minimum (`docs/hackathon/mvp-cd/specs/parameters.md`, Layout and Binding).
enum Tuner {
    static let id = EffectID.package("tuner")
    static let directory = "\(CatalogSide.folder)/tuner.lens"
    static let manifestPath = "\(directory)/manifest.json"
    static let sourcePath = "\(directory)/effect.metal"
    static let manifest =
        #"{"formatVersion": 1, "name": "Tuner", "parameters": [{"id": "strength", "label": "Strength", "type": "float", "min": 0, "max": 1, "default": 0.5}, {"id": "mode", "label": "Mode", "type": "choice", "options": ["Soft", "Hard"], "default": "Soft"}]}"#
    static let source = "kernel void effect() {}"

    // The four little-endian bytes each field holds, as the block has them.
    static let halfStrength: [UInt8] = [0x00, 0x00, 0x00, 0x3F]  // 0.5, the default
    static let quarterStrength: [UInt8] = [0x00, 0x00, 0x80, 0x3E]  // 0.25
    static let threeQuartersStrength: [UInt8] = [0x00, 0x00, 0x40, 0x3F]  // 0.75
    static let fullStrength: [UInt8] = [0x00, 0x00, 0x80, 0x3F]  // 1.0
    static let softMode: [UInt8] = [0x00, 0x00, 0x00, 0x00]  // index 0, the default
    static let hardMode: [UInt8] = [0x01, 0x00, 0x00, 0x00]  // index 1

    /// The block for a `strength` word and a `mode` word, with the padding that brings it to 16 bytes.
    static func block(strength: [UInt8], mode: [UInt8]) -> [UInt8] {
        strength + mode + [UInt8](repeating: 0, count: 8)
    }

    /// Writes the package into the folder the way an editor would.
    static func write(into fileSystem: InMemoryFileSystemGateway) {
        fileSystem.write(manifestPath, manifest)
        fileSystem.write(sourcePath, source)
    }
}

/// The loopback with the extension up, the host started and the catalog running on the bundled effect, started the same
/// way `EffectCatalogIntegrationTests` starts it (`LoopbackRig(effects: .real, catalog: .real)`). A parameter test installs
/// `Tuner`, chooses it, writes its parameters through the catalog's UseCase and draws camera frames, and reads each
/// committed pass's block off the fake GPU.
@MainActor
final class ParameterSession {
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

    static func start() async throws -> ParameterSession {
        let rig = LoopbackRig(effects: .real, catalog: .real)
        let side = try #require(rig.host.catalog)
        let relay = await rig.startExtension()
        try await rig.startHost()
        let running = try #require(await rig.startCatalog())
        return ParameterSession(rig: rig, side: side, relay: relay, running: running)
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

    /// Sets the parameter `id` of the chosen effect through the catalog's UseCase, as the panel does, and returns once
    /// the call has returned. What the state shows is for the test to wait for with `rig.pumpHost(until:)`.
    func set(_ id: String, to value: EffectParameterValue) async {
        guard let useCase = rig.host.catalog?.useCase else {
            Issue.record("set needs a host built with catalog: .real")
            return
        }
        await useCase.setParameter(id, to: value)
    }

    /// Puts every parameter of the chosen effect back to its default through the catalog's UseCase.
    func resetParameters() async {
        guard let useCase = rig.host.catalog?.useCase else {
            Issue.record("resetParameters needs a host built with catalog: .real")
            return
        }
        await useCase.resetParameters()
    }

    /// One camera frame through the runtime, and the extension has received it.
    func drawFrame() async {
        cameraFrames += 1
        let camera = FakeSurfaceHandle(id: UInt32(cameraFrames))
        await rig.captureThroughRuntime(camera, at: UInt64(cameraFrames) * 1_000)
        await rig.pumpExtension(untilReceived: cameraFrames)
    }

    /// The passes the fake GPU has committed so far, in submission order.
    var passes: [ComputePass] {
        rig.host.gpu.submissions.values.map(\.pass)
    }

    /// The newest committed pass.
    func lastPass() throws -> ComputePass {
        try #require(passes.last, "no pass was committed")
    }
}
