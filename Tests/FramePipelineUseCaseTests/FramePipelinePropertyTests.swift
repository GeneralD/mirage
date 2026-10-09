import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

/// One thing that can happen to the pipeline between two observations.
private enum Step: CaseIterable {
    case emit
    case tick
    case drain
    case toggleDrops
    case destinationLost
    case stop
}

/// What the test expects the subject to have done, tracked independently of it.
private struct Model {
    var running = true
    var dropping = false
    var pending = false
    var emitted = 0
    var processed = 0
    var nextTime: UInt64 = 1_000
}

@Suite("FramePipelineUseCaseImpl properties", .timeLimit(.minutes(1)))
struct FramePipelinePropertyTests {
    @Test("random interleavings keep leases balanced and frames ordered", arguments: standardSeeds)
    func invariantsHold(seed: UInt64) async throws {
        var generator = SeededGenerator(seed: seed)
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        // Mutable: advanced once per step; it is the oracle the subject is judged against.
        var model = Model()

        for _ in 0..<60 {
            let step = Step.allCases[Int(generator.next() % UInt64(Step.allCases.count))]
            apply(step, to: &model, on: rig)
            // Release exactly once, at every step: the pool holds the one pending
            // frame (and nothing else) until the subject lets it go.
            #expect(rig.surfaces.liveCount == (model.pending ? 1 : 0))
            #expect(rig.surfaces.refusedReleases == 0)
        }
        rig.subject.stop()
        rig.executor.drain()

        #expect(rig.subject.phase == .stopped)
        let stats = rig.subject.stats
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
        #expect(stats.framesReceived == model.emitted)
        #expect(stats.framesSent + stats.framesDropped == model.processed)
        #expect(stats.framesSent + stats.framesDropped <= stats.framesReceived)
        #expect(stats.framesSent == rig.sink.sent.count)
        let times = rig.sink.sent.values.map(\.presentationTime)
        #expect(times == times.sorted())
    }

    private func apply(_ step: Step, to model: inout Model, on rig: Rig) {
        switch step {
        case .emit where model.running:
            model.nextTime += 33_000_000
            guard rig.emit(at: model.nextTime) != nil else { return }
            model.emitted += 1
            model.pending = true
        case .tick where model.running:
            rig.scheduler.tick()
            model.processed += model.pending ? 1 : 0
            model.pending = false
        case .drain:
            rig.executor.drain()
            // `stop()` releases the pending frame on the executor, so it is only
            // gone once that work has run.
            model.pending = model.pending && model.running
        case .toggleDrops where model.running:
            model.dropping.toggle()
            rig.sink.dropSends(with: model.dropping ? .sendFailed(code: 7) : nil)
        case .destinationLost where model.running:
            rig.sink.emit(.disconnected(.destinationLost))
        case .stop where model.running:
            rig.subject.stop()
            model.running = false
        default:
            return
        }
    }
}
