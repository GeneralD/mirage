import Domain
import TestDoubles
import TestSupport
import Testing

@testable import PreviewDataSource

/// Seeded interleavings of everything that can reach the preview: presents,
/// attaches (good, foreign, or with a kernel that does not compile), GPU
/// completions (clean or faulted), leases released early (stale tokens) and
/// executor drains. Whatever the order, every present completes exactly once,
/// no more than one draw is ever in flight, no older frame is drawn after a
/// newer one, every bind is unbound once and every lease comes back.
@Suite("PreviewDataSource properties", .timeLimit(.minutes(1)))
struct PreviewDataSourcePropertyTests {
    private enum Step: CaseIterable {
        case present, present2, attach, attachForeign, toggleCompileFailure, complete, completeFaulted, releaseEarly, drain
    }

    private static let steps = 80

    @Test("every present completes exactly once, one draw at most is in flight, and frames are drawn oldest first", arguments: Seeds.range(0..<50))
    func exactlyOnce(seed: UInt64) async throws {
        var generator = SeededGenerator(seed: seed)
        let rig = PreviewRig(capacity: Self.steps)
        var frames: [FrameRef] = []
        var compileFails = false

        for _ in 0..<Self.steps {
            switch Step.allCases[Int(generator.next() % UInt64(Step.allCases.count))] {
            case .present, .present2:
                let frame = try rig.frame(frames.count + 1)
                frames.append(frame)
                rig.present(frame)
            case .attach:
                try await rig.attach()
            case .attachForeign:
                await #expect(throws: PreviewError.foreignTarget) { try await rig.attach(ForeignTarget()) }
            case .toggleCompileFailure:
                compileFails.toggle()
                rig.compiler.failCompile(of: PreviewKernel.source, with: compileFails ? ShaderDiagnostics(message: "scripted", code: 1) : nil)
            case .complete:
                if let draw = rig.preview.pending.first { rig.preview.complete(draw) }
            case .completeFaulted:
                let fault = GPUCompletion(gpuStart: 0, gpuEnd: 0, error: RawGPUError(domain: "MTLCommandBufferErrorDomain", code: 2))
                if let draw = rig.preview.pending.first { rig.preview.complete(draw, with: fault) }
            case .releaseEarly where !frames.isEmpty:
                rig.pool.release(frames[Int(generator.next() % UInt64(frames.count))].token)
            case .releaseEarly:
                break
            case .drain:
                rig.executor.drain()
            }
            #expect(rig.preview.pending.count <= 1, "seed \(seed): more than one draw in flight")
        }
        settle(rig)

        let counts = Dictionary(grouping: rig.completed.values, by: { $0 }).mapValues(\.count)
        #expect(
            counts == Dictionary(uniqueKeysWithValues: frames.indices.map { ($0 + 1, 1) }), "seed \(seed): not every frame completed exactly once")
        let drawn = rig.preview.draws.values.compactMap(rig.frameNumber(of:))
        #expect(drawn == drawn.sorted() && Set(drawn).count == drawn.count, "seed \(seed): drawn out of order \(drawn)")
        #expect(rig.textures.isBalanced, "seed \(seed)")
        #expect(rig.pool.liveCount == 0, "seed \(seed): a lease never came back")
    }

    /// Runs everything still queued and finishes every draw still in flight.
    private func settle(_ rig: PreviewRig) {
        rig.executor.drain()
        while let draw = rig.preview.pending.first {
            rig.preview.complete(draw)
            rig.executor.drain()
        }
    }
}

private final class ForeignTarget: PreviewTargetHandle, Sendable {
    var backing: AnyObject { self }
}
