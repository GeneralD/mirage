import Dependencies
import Domain

/// The authoring policy of the command-line tool. `validate` answers what the Repository's check
/// answers, unchanged; `scaffold` answers the Repository's path, and wraps its problem as
/// `AuthoringFailure.scaffold`. `render` reads the image, leases two surfaces, runs the effect once and
/// writes what it produced; each step goes through its Repository. The frame executor is resolved only
/// to run the surface pool's calls on the executor it lives on.
public struct EffectAuthoringUseCaseImpl: EffectAuthoringUseCase, Sendable {
    @Dependency(\.effectPackageRepository) private var packages
    @Dependency(\.stillImageRepository) private var stillImages
    @Dependency(\.surfaceRepository) private var surfaces
    @Dependency(\.effectRuntimeRepository) private var effectRuntime
    @Dependency(\.frameExecutor) private var frameExecutor

    public init() {}

    public func validate(packageAt path: String) async -> Result<EffectSource, AuthoringFailure> {
        await packages.check(packageAt: path)
    }

    public func scaffold(named name: String, in folder: String) async -> Result<String, AuthoringFailure> {
        await packages.scaffold(named: name, in: folder).mapError { AuthoringFailure.scaffold($0) }
    }

    public func render(_ effect: EffectReference, from input: String, to output: String) async -> Result<StillImageSize, AuthoringFailure> {
        switch await stillImages.read(input) {
        case .failure(let problem):
            return .failure(.image(problem))
        case .success(let image):
            switch await source(of: effect) {
            case .failure(let failure):
                return .failure(failure)
            case .success(let source):
                return await renderPass(source, of: image, to: output)
            }
        }
    }
}

// MARK: - Steps

extension EffectAuthoringUseCaseImpl {
    /// The source the effect names. A package is checked and its failure answered unchanged; a bundled
    /// effect is read by the name it shows, and a name the app does not ship is `bundledEffectNotFound`.
    private func source(of effect: EffectReference) async -> Result<EffectSource, AuthoringFailure> {
        switch effect {
        case .package(let path):
            return await packages.check(packageAt: path)
        case .bundled(let name):
            switch await packages.source(of: EffectID(origin: .bundled, key: name)) {
            case .success(let source):
                return .success(source)
            case .failure(.sourceMissing):
                return .failure(.bundledEffectNotFound(name: name))
            case .failure(let problem):
                return .failure(.package(problem))
            }
        }
    }

    /// One pass over one image: leases the surfaces, runs the effect, gives the surfaces back, and writes
    /// the output. The leases begin and end in one executor step each, so a pass costs exactly two hops.
    private func renderPass(_ source: EffectSource, of image: StillImage, to output: String) async -> Result<StillImageSize, AuthoringFailure> {
        let pool = surfaces
        guard let lease = await onExecutor({ Self.leaseSurfaces(for: image, in: pool) }) else {
            return .failure(.surfaceUnavailable)
        }
        let applied = await apply(source, through: lease)
        let rendered = await onExecutor({ Self.finish(lease, applied, in: pool) })
        switch rendered {
        case .failure(let failure):
            return .failure(failure)
        case .success(let frame):
            switch await stillImages.write(frame, to: output) {
            case .failure(let problem):
                return .failure(.image(problem))
            case .success:
                return .success(StillImageSize(width: frame.width, height: frame.height))
            }
        }
    }

    /// Prepares the effect with its default block, then applies it once from the input surface into the output.
    private func apply(_ source: EffectSource, through lease: Lease) async -> Result<Void, AuthoringFailure> {
        switch await effectRuntime.prepare(source, parameters: DefaultParameterBlock.make(for: source.parameters)) {
        case .failure(let failure):
            return .failure(.effect(failure))
        case .success:
            let context = FrameContext(presentationTime: .zero, frameIndex: 0)
            switch await effectRuntime.apply(input: lease.input, output: lease.output, frameContext: context) {
            case .failure(let failure):
                return .failure(.effect(failure))
            case .success:
                return .success(())
            }
        }
    }
}

// MARK: - Surfaces (run on the executor)

extension EffectAuthoringUseCaseImpl {
    /// Takes the input and the output surface, both at the image's size, and uploads the image into the input.
    /// A surface that cannot be taken or filled gives back the ones already taken, so nothing stays leased.
    private static func leaseSurfaces(for image: StillImage, in pool: any SurfaceRepository) -> Lease? {
        let descriptor = SurfaceDescriptor.bgra(width: image.width, height: image.height)
        guard let input = allocate(descriptor, in: pool) else { return nil }
        guard let output = allocate(descriptor, in: pool) else {
            pool.release(input.token)
            return nil
        }
        guard pool.upload(image, to: input.token) else {
            pool.release(input.token)
            pool.release(output.token)
            return nil
        }
        return Lease(input: input, output: output)
    }

    private static func allocate(_ descriptor: SurfaceDescriptor, in pool: any SurfaceRepository) -> FrameRef? {
        guard let token = try? pool.allocate(descriptor) else { return nil }
        return FrameRef(token: token, descriptor: descriptor, presentationTime: .zero)
    }

    /// Reads the output back when the pass succeeded, then gives both surfaces back whatever the outcome.
    private static func finish(_ lease: Lease, _ applied: Result<Void, AuthoringFailure>, in pool: any SurfaceRepository)
        -> Result<StillImage, AuthoringFailure>
    {
        let rendered = applied.flatMap { _ in Self.readBack(lease.output.token, in: pool) }
        pool.release(lease.input.token)
        pool.release(lease.output.token)
        return rendered
    }

    private static func readBack(_ token: SurfaceToken, in pool: any SurfaceRepository) -> Result<StillImage, AuthoringFailure> {
        guard let image = pool.download(from: token) else { return .failure(.surfaceUnavailable) }
        return .success(image)
    }

    /// Runs `work` on the frame executor, where the surface pool lives, and answers what it returns.
    private func onExecutor<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        let executor = frameExecutor
        return await withCheckedContinuation { continuation in
            executor.run { continuation.resume(returning: work()) }
        }
    }
}

/// The two surfaces of one pass, each as the frame the effect runtime takes.
private struct Lease: Sendable {
    let input: FrameRef
    let output: FrameRef
}
