import Dependencies
import Domain

/// One effect pass, one command buffer: resolves the two leases through the
/// pool, binds them as textures, commits a single `ComputePass` and maps the
/// raw completion onto `EffectFailure` (`GPUCompletionMapping`). Every decision
/// the thin `MetalGateway` leaves open is taken here and tested against the fakes.
///
/// Executor-confined: the surface pool is confined to `FrameExecutor`, so each
/// pass starts with a hop there and resolves, binds and commits on it; the GPU
/// context is made there on the first pass and kept. The completion arrives on
/// the GPU's completion thread and touches only the texture gateway (stateless
/// live, locked fake), never the pool or the context.
public final class GPURenderDataSourceImpl: @unchecked Sendable {
    @Dependency(\.gpuGateway) private var gpu
    @Dependency(\.textureCacheGateway) private var textures
    @Dependency(\.surfacePool) private var pool
    @Dependency(\.frameExecutor) private var executor
    @Dependency(\.errorLog) private var errorLog

    // Executor-confined. Kept once made; a failed `makeContext` is not remembered,
    // so the next pass asks again instead of failing for the rest of the session.
    private var context: (any GPUContextHandle)?

    public init() {}
}

extension GPURenderDataSourceImpl: GPURenderer {
    public func render(
        library: any LibraryHandle, input: SurfaceToken, output: SurfaceToken, uniforms: EffectUniforms
    ) async -> Result<GPUTiming, EffectFailure> {
        await withCheckedContinuation { continuation in
            executor.run { [self] in
                commit(library: library, input: input, output: output, uniforms: uniforms) { continuation.resume(returning: $0) }
            }
        }
    }
}

extension GPURenderDataSourceImpl {
    private typealias Finish = @Sendable (Result<GPUTiming, EffectFailure>) -> Void

    /// Runs on the executor and calls `finish` exactly once: at once when the pass
    /// cannot be committed, otherwise from the command buffer's completion. The
    /// tokens are resolved before any gateway is asked for anything, so a stale
    /// lease costs no context, no binding and no command buffer.
    private func commit(library: any LibraryHandle, input: SurfaceToken, output: SurfaceToken, uniforms: EffectUniforms, finish: @escaping Finish) {
        guard let source = pool.handle(for: input), let target = pool.handle(for: output), let geometry = pool.descriptor(for: output) else {
            return finish(.failure(.invalidResource))
        }
        guard let context = currentContext() else { return finish(.failure(.internalError)) }
        let bound: [any TextureHandle]
        do {
            bound = try bind([source, target], on: context)
        } catch {
            errorLog.record(.pipeline, "effect pass skipped, a surface could not be bound: \(error)")
            return finish(.failure(.invalidResource))
        }
        let pass = ComputePass(
            kernel: library, textures: bound, uniforms: uniforms, grid: .covering(width: geometry.width, height: geometry.height))
        do {
            try gpu.encodeAndCommit(pass, on: context) { [self] completion in
                unbind(bound)
                finish(GPUCompletionMapping.result(of: completion))
            }
        } catch {
            // Nothing was committed, so no completion will ever arrive for these textures.
            unbind(bound)
            errorLog.record(.pipeline, "effect pass not committed: \(error)")
            finish(.failure(.internalError))
        }
    }

    private func currentContext() -> (any GPUContextHandle)? {
        if let context { return context }
        do {
            let made = try gpu.makeContext()
            context = made
            return made
        } catch {
            errorLog.record(.pipeline, "no GPU context for the effect pass: \(error)")
            return nil
        }
    }

    /// Binds in order (input at index 0, output last). When one bind fails, the
    /// ones already made are given back before the error propagates, so a failed
    /// pass leaves nothing bound.
    private func bind(_ surfaces: [any SurfaceHandle], on context: any GPUContextHandle) throws -> [any TextureHandle] {
        try surfaces.reduce(into: [any TextureHandle]()) { bound, surface in
            do {
                bound.append(try textures.bind(surface, on: context))
            } catch {
                unbind(bound)
                throw error
            }
        }
    }

    /// Each texture goes back once. The gateway refuses only a handle it did not
    /// issue, which these never are; a refusal is logged rather than retried.
    private func unbind(_ bound: [any TextureHandle]) {
        for texture in bound {
            do {
                try textures.unbind(texture)
            } catch {
                errorLog.record(.pipeline, "texture unbind refused: \(error)")
            }
        }
    }
}
