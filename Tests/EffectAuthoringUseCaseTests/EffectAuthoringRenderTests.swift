import Dependencies
import Domain
import EffectAuthoringUseCase
import TestDoubles
import TestSupport
import Testing

/// The values the render tests share: the input the still repository answers for, the output it writes to,
/// and the effect the package and bundled repositories answer with.
private enum Fixture {
    static let input = "/work/in.png"
    static let output = "/work/out.png"
    static let glowPath = "/work/glow.lens"
    static let image = StillImage(width: 2, height: 1, bgra: [1, 2, 3, 4, 5, 6, 7, 8])
    static let rendered = StillImage(width: 2, height: 1, bgra: [8, 7, 6, 5, 4, 3, 2, 1])
    static let size = StillImageSize(width: 2, height: 1)
    static let glow = EffectSource(name: "Glow", source: "kernel void effect() {}")
    static let glowID = EffectID(origin: .bundled, key: "Glow")
}

/// A `SurfaceRepository` that forwards to `inner` and counts the `download`s it is asked for, so a test can tell
/// that a pass which did not succeed never reads its output back.
private final class SpySurfaces: SurfaceRepository, Sendable {
    let inner: FakeSurfaceRepository
    private let downloads = Locked(0)

    init(inner: FakeSurfaceRepository) {
        self.inner = inner
    }

    var liveCount: Int { inner.liveCount }
    var downloadCount: Int { downloads.current }

    func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken? {
        try inner.allocate(descriptor)
    }

    func allocate(_ descriptor: SurfaceDescriptor, filledWith byte: UInt8) throws -> SurfaceToken? {
        try inner.allocate(descriptor, filledWith: byte)
    }

    func upload(_ image: StillImage, to token: SurfaceToken) -> Bool {
        inner.upload(image, to: token)
    }

    func download(from token: SurfaceToken) -> StillImage? {
        downloads.withLock { $0 += 1 }
        return inner.download(from: token)
    }

    @discardableResult
    func release(_ token: SurfaceToken) -> Bool {
        inner.release(token)
    }

    func releaseAll() {
        inner.releaseAll()
    }
}

/// `EffectAuthoringUseCaseImpl.render` over fakes of its Repositories and a recording frame executor. The test
/// scripts what each Repository answers and completes the runtime's calls by hand, so what is proven here is the
/// policy: the order of the steps, the surfaces each one is given, what each failure answers, and that every lease ends.
@Suite("EffectAuthoringUseCase render", .timeLimit(.minutes(1)))
struct EffectAuthoringRenderTests {
    private struct Rig {
        let stillImages: FakeStillImageRepository
        let packages: FakeEffectPackageRepository
        let runtime: FakeEffectRuntimeRepository
        let executor: RecordingFrameExecutor
        let surfaces: SpySurfaces
        let subject: EffectAuthoringUseCaseImpl

        init(capacity: Int = 4) {
            let stillImages = FakeStillImageRepository()
            let packages = FakeEffectPackageRepository()
            let runtime = FakeEffectRuntimeRepository()
            let executor = RecordingFrameExecutor()
            let surfaces = SpySurfaces(inner: FakeSurfaceRepository(pool: FakeSurfacePool(capacity: capacity)))
            self.stillImages = stillImages
            self.packages = packages
            self.runtime = runtime
            self.executor = executor
            self.surfaces = surfaces
            subject = withDependencies {
                $0.stillImageRepository = stillImages
                $0.effectPackageRepository = packages
                $0.effectRuntimeRepository = runtime
                $0.surfaceRepository = surfaces
                $0.frameExecutor = executor
            } operation: {
                EffectAuthoringUseCaseImpl()
            }
        }

        var pool: FakeSurfacePool { surfaces.inner.pool }

        /// Starts `render` on a task of its own, so the test can step it through the executor and the runtime.
        func start(_ effect: EffectReference) -> Task<Result<StillImageSize, AuthoringFailure>, Never> {
            let subject = subject
            return Task { await subject.render(effect, from: Fixture.input, to: Fixture.output) }
        }

        /// Runs the executor hop the render queued as its `n`th (counted from 1), once it has queued it.
        func runHop(_ n: Int) async {
            await executor.enqueued.waitForCount(n)
            executor.drain()
        }

        /// The `prepare` the render made, once it has made it.
        func prepareRequest() async -> FakeEffectRuntimeRepository.PrepareRequest {
            await runtime.prepareRequests.waitForCount(1)
            return runtime.prepareRequests.values[0]
        }

        /// The `apply` the render made, once it has made it.
        func applyRequest() async -> FakeEffectRuntimeRepository.ApplyRequest {
            await runtime.applyRequests.waitForCount(1)
            return runtime.applyRequests.values[0]
        }

        /// Answers the render's `prepare` and `apply` with success, the output surface holding `output`, and runs
        /// the hop that gives the surfaces back. The render must already be waiting for its `prepare`.
        func succeedThroughEffect(output: StillImage) async {
            let prepare = await prepareRequest()
            runtime.completePrepare(prepare, with: .success(()))
            let apply = await applyRequest()
            pool.setPixels(output, of: apply.output.token)
            runtime.completeApply(apply, with: .success(()))
            await runHop(2)
        }
    }

    // MARK: - Steps of a successful pass

    @Test(
        "a bundled effect reads its image, uploads it into one of two surfaces, prepares its source with the default block, and applies it at time zero and frame zero"
    )
    func bundledEffectIsPreparedAndApplied() async {
        let rig = Rig()
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)
        let task = rig.start(.bundled(name: "Glow"))

        await rig.runHop(1)
        let prepare = await rig.prepareRequest()
        #expect(prepare.effect == Fixture.glow)
        #expect(prepare.parameters == DefaultParameterBlock.make(for: Fixture.glow.parameters))
        #expect(rig.stillImages.reads.values == [Fixture.input])
        #expect(rig.packages.sourceRequests.values == [Fixture.glowID])
        rig.runtime.completePrepare(prepare, with: .success(()))

        let apply = await rig.applyRequest()
        #expect(rig.pool.uploads.values.first?.image == Fixture.image)
        #expect(rig.pool.uploads.values.first?.token == apply.input.token)
        #expect(apply.input.token != apply.output.token)
        #expect(apply.input.descriptor == SurfaceDescriptor.bgra(width: 2, height: 1))
        #expect(apply.output.descriptor == SurfaceDescriptor.bgra(width: 2, height: 1))
        #expect(apply.frameContext == FrameContext(presentationTime: .zero, frameIndex: 0))
        #expect(rig.surfaces.liveCount == 2)
        rig.runtime.completeApply(apply, with: .success(()))

        await rig.runHop(2)
        #expect(await task.value == .success(Fixture.size))
    }

    @Test("a successful apply writes the output surface's image once to the output path, answers its size, and leaves no surface live")
    func successfulApplyWritesTheOutput() async {
        let rig = Rig()
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)
        let task = rig.start(.bundled(name: "Glow"))

        await rig.runHop(1)
        await rig.succeedThroughEffect(output: Fixture.rendered)

        #expect(await task.value == .success(Fixture.size))
        #expect(rig.stillImages.writes.values == [FakeStillImageRepository.Write(path: Fixture.output, image: Fixture.rendered)])
        #expect(rig.surfaces.liveCount == 0)
    }

    @Test("a render hops onto the executor exactly twice, to lease its surfaces and to give them back")
    func renderHopsTwice() async {
        let rig = Rig()
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)
        let task = rig.start(.bundled(name: "Glow"))

        await rig.runHop(1)
        await rig.succeedThroughEffect(output: Fixture.rendered)
        _ = await task.value

        #expect(rig.executor.enqueued.count == 2)
    }

    @Test("a package effect is checked by its path, prepared with the source the check answers, and never asks the catalog for a bundled source")
    func packageEffectIsChecked() async {
        let rig = Rig()
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.scriptCheck(.success(Fixture.glow), for: Fixture.glowPath)
        let task = rig.start(.package(path: Fixture.glowPath))

        await rig.runHop(1)
        let prepare = await rig.prepareRequest()
        #expect(prepare.effect == Fixture.glow)
        #expect(rig.packages.checkRequests.values == [Fixture.glowPath])
        #expect(rig.packages.sourceRequests.count == 0)
        rig.runtime.completePrepare(prepare, with: .success(()))
        let apply = await rig.applyRequest()
        rig.pool.setPixels(Fixture.rendered, of: apply.output.token)
        rig.runtime.completeApply(apply, with: .success(()))
        await rig.runHop(2)

        #expect(await task.value == .success(Fixture.size))
    }

    // MARK: - Answers before any surface is leased

    @Test("an input that cannot be read answers its image problem, and neither leases a surface nor prepares anything")
    func unreadableInputAnswersItsProblem() async {
        let rig = Rig()
        rig.stillImages.script(.failure(.notAnImage(path: Fixture.input)), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)

        #expect(
            await rig.subject.render(.bundled(name: "Glow"), from: Fixture.input, to: Fixture.output)
                == .failure(.image(.notAnImage(path: Fixture.input))))
        #expect(rig.executor.enqueued.count == 0)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.runtime.prepareRequests.count == 0)
        #expect(rig.stillImages.writes.count == 0)
    }

    @Test("a bundled name the repository has no source for answers bundledEffectNotFound with that name, and leases no surface")
    func unknownBundledNameIsNotFound() async {
        let rig = Rig()
        let missing = EffectID(origin: .bundled, key: "Missing")
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.failure(.sourceMissing), for: missing)

        #expect(
            await rig.subject.render(.bundled(name: "Missing"), from: Fixture.input, to: Fixture.output)
                == .failure(.bundledEffectNotFound(name: "Missing")))
        #expect(rig.executor.enqueued.count == 0)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.runtime.prepareRequests.count == 0)
    }

    @Test("a package that cannot be checked answers the check's failure unchanged, and leases no surface")
    func uncheckedPackageAnswersItsFailure() async {
        let rig = Rig()
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.scriptCheck(.failure(.package(.manifestMissing)), for: Fixture.glowPath)

        #expect(
            await rig.subject.render(.package(path: Fixture.glowPath), from: Fixture.input, to: Fixture.output)
                == .failure(.package(.manifestMissing)))
        #expect(rig.executor.enqueued.count == 0)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.runtime.prepareRequests.count == 0)
    }

    // MARK: - Failures after a surface is leased

    @Test("a pool with no second surface answers surfaceUnavailable, gives the first one back, and prepares nothing")
    func poolWithOneSurfaceIsUnavailable() async {
        let rig = Rig(capacity: 1)
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)
        let task = rig.start(.bundled(name: "Glow"))

        await rig.runHop(1)

        #expect(await task.value == .failure(.surfaceUnavailable))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.runtime.prepareRequests.count == 0)
        #expect(rig.executor.enqueued.count == 1)
    }

    @Test("a surface that refuses the image answers surfaceUnavailable, gives both surfaces back, and prepares nothing")
    func refusedUploadGivesBothBack() async {
        let rig = Rig()
        rig.pool.failUploads(true)
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)
        let task = rig.start(.bundled(name: "Glow"))

        await rig.runHop(1)

        #expect(await task.value == .failure(.surfaceUnavailable))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.runtime.prepareRequests.count == 0)
    }

    @Test("a compile failure answers effect(compileFailed), never applies, and gives both surfaces back")
    func compileFailureIsAnswered() async {
        let rig = Rig()
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)
        let task = rig.start(.bundled(name: "Glow"))

        await rig.runHop(1)
        let prepare = await rig.prepareRequest()
        rig.runtime.completePrepare(prepare, with: .failure(.compileFailed))
        await rig.runHop(2)

        #expect(await task.value == .failure(.effect(.compileFailed)))
        #expect(rig.runtime.applyRequests.count == 0)
        #expect(rig.surfaces.liveCount == 0)
    }

    @Test("an apply failure answers effect(timeout), reads no output back, and gives both surfaces back")
    func applyFailureIsAnswered() async {
        let rig = Rig()
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)
        let task = rig.start(.bundled(name: "Glow"))

        await rig.runHop(1)
        let prepare = await rig.prepareRequest()
        rig.runtime.completePrepare(prepare, with: .success(()))
        let apply = await rig.applyRequest()
        rig.runtime.completeApply(apply, with: .failure(.timeout))
        await rig.runHop(2)

        #expect(await task.value == .failure(.effect(.timeout)))
        #expect(rig.surfaces.downloadCount == 0)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.stillImages.writes.count == 0)
    }

    @Test("an output the surface cannot read back answers surfaceUnavailable, writes nothing, and gives both surfaces back")
    func unreadableOutputIsUnavailable() async {
        let rig = Rig()
        rig.pool.failDownloads(true)
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)
        let task = rig.start(.bundled(name: "Glow"))

        await rig.runHop(1)
        await rig.succeedThroughEffect(output: Fixture.rendered)

        #expect(await task.value == .failure(.surfaceUnavailable))
        #expect(rig.stillImages.writes.count == 0)
        #expect(rig.surfaces.liveCount == 0)
    }

    @Test("an output that cannot be written answers image(unwritable) and gives both surfaces back")
    func unwritableOutputIsAnswered() async {
        let rig = Rig()
        rig.stillImages.failWrites(with: .unwritable(path: Fixture.output))
        rig.stillImages.script(.success(Fixture.image), for: Fixture.input)
        rig.packages.script(.success(Fixture.glow), for: Fixture.glowID)
        let task = rig.start(.bundled(name: "Glow"))

        await rig.runHop(1)
        await rig.succeedThroughEffect(output: Fixture.rendered)

        #expect(await task.value == .failure(.image(.unwritable(path: Fixture.output))))
        #expect(rig.surfaces.liveCount == 0)
    }
}
