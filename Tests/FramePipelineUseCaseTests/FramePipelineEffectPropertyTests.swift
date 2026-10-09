import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

/// A pass the model knows is in flight: its input, the order it started in (which is
/// also its `apply` request and its work item, as nothing else starts work here), and —
/// once the runtime has answered — the frame its completion will send.
private struct ModelPass {
    let input: FrameRef
    let index: Int
    var sends: FrameRef?
}

/// What the test expects the subject to have done, tracked independently of it.
private struct EffectModel {
    var running = true
    /// `stop()` was called and its executor work has not run yet.
    var stopQueued = false
    var latest: FrameRef?
    var pass: ModelPass?
    var passesStarted = 0
    var emitted = 0
    /// Ticks that found a frame in the slot: each ends in exactly one send, one drop,
    /// or (at stop) one abandoned pass.
    var ticksTaking = 0
    var sent: [FrameRef] = []
    var capDrops = 0
    /// Answers drained after `stop()` disconnected the sink: their frame drops as `.notConnected`.
    var stopDrops = 0
    var abandoned = 0
    var applied = 0
    var failures: [EffectFailure: Int] = [:]

    /// The leases the pipeline holds: the slot's frame, and a pass's input and output.
    var live: Int { (latest == nil ? 0 : 1) + (pass == nil ? 0 : 2) }
}

/// Which paths a run took, so the suite can prove the seeds reach all of them.
private struct EffectCoverage {
    var capDrops = 0
    var applied = 0
    var failed = 0
    var abandoned = 0
    var stopDrops = 0
}

@Suite("FramePipelineUseCaseImpl effect stage properties", .timeLimit(.minutes(1)))
struct FramePipelineEffectPropertyTests {
    @Test(
        "any order of capture, tick, answer, failure, drain and stop keeps every lease balanced, the stream in order and every taken frame accounted for",
        arguments: Seeds.range(0..<50))
    func invariantsHold(seed: UInt64) async throws {
        _ = try await run(seed: seed)
    }

    @Test("across the seeds every path is taken: applied, failed, cap drop, abandoned at stop, answered into a stopping sink")
    func seedsCoverEveryPath() async throws {
        var total = EffectCoverage()
        for seed in Seeds.range(0..<50) {
            let coverage = try await run(seed: seed)
            total.capDrops += coverage.capDrops
            total.applied += coverage.applied
            total.failed += coverage.failed
            total.abandoned += coverage.abandoned
            total.stopDrops += coverage.stopDrops
        }
        #expect(total.capDrops > 0, "no seed ever hit the in-flight cap")
        #expect(total.applied > 0, "no seed ever applied an effect")
        #expect(total.failed > 0, "no seed ever passed a failure through")
        #expect(total.abandoned > 0, "no seed ever stopped with a pass in flight")
        #expect(total.stopDrops > 0, "no seed ever drained an answer after stop")
    }

    private func run(seed: UInt64) async throws -> EffectCoverage {
        var generator = SeededGenerator(seed: seed)
        let rig = Rig(capacity: 4)
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        // Mutable: advanced once per step; it is the oracle the subject is judged against.
        var model = EffectModel()
        var time: UInt64 = 1_000_000

        for _ in 0..<80 {
            time += UInt64.random(in: 1...40_000_000, using: &generator)
            try await step(Int.random(in: 0..<41, using: &generator), at: time, model: &model, rig: rig, generator: &generator)
            #expect(rig.surfaces.liveCount == model.live, "seed \(seed): the pipeline holds exactly the slot and the pass")
            #expect(rig.surfaces.refusedReleases == 0, "seed \(seed): no lease released twice")
        }

        if model.running { try await step(40, at: time, model: &model, rig: rig, generator: &generator) }
        drain(&model, rig)
        // The cancelled `apply`s resume with `.internalError`; their answers are ignored.
        await rig.work.finished.waitForCount(rig.work.started.count)
        rig.executor.drain()

        let stats = rig.subject.stats
        #expect(rig.surfaces.liveCount == 0, "seed \(seed)")
        #expect(rig.surfaces.refusedReleases == 0, "seed \(seed)")
        #expect(rig.sink.sent.values == model.sent, "seed \(seed): success sends the output, any failure the input itself")
        let times = rig.sink.sent.values.map(\.presentationTime)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 }, "seed \(seed): PTS strictly increasing")
        #expect(stats.framesReceived == model.emitted, "seed \(seed)")
        #expect(stats.framesSent == model.sent.count, "seed \(seed)")
        #expect(stats.framesDropped == model.capDrops + model.stopDrops, "seed \(seed)")
        #expect(stats.dropReasons[.inFlightCapReached, default: 0] == model.capDrops, "seed \(seed)")
        #expect(stats.dropReasons[.poolExhausted] == nil, "seed \(seed): a pool of four never runs out")
        #expect(
            model.ticksTaking == stats.framesSent + stats.framesDropped + model.abandoned,
            "seed \(seed): every frame a tick took was sent, counted as a drop, or abandoned by stop")
        #expect(stats.effectsApplied == model.applied, "seed \(seed)")
        #expect(stats.effectFailures == model.failures, "seed \(seed)")
        return EffectCoverage(
            capDrops: model.capDrops, applied: model.applied, failed: model.failures.values.reduce(0, +),
            abandoned: model.abandoned, stopDrops: model.stopDrops)
    }

    /// `roll` in 0..<41 picks the step; stop is rare (40) so most runs do real work first.
    private func step(
        _ roll: Int, at time: UInt64, model: inout EffectModel, rig: Rig, generator: inout SeededGenerator
    ) async throws {
        switch roll {
        case 0..<8 where model.running:
            let frame = try #require(rig.emit(at: time), "the camera is never refused a surface")
            model.emitted += 1
            model.latest = frame
        case 8..<16 where model.running:
            rig.scheduler.tick()
            tick(&model)
            #expect(rig.work.started.count == model.passesStarted)
        case 16..<24 where model.running:
            try await answer(.success(()), model: &model, rig: rig)
        case 24..<30 where model.running:
            let failure = everyEffectFailure[Int.random(in: 0..<everyEffectFailure.count, using: &generator)]
            try await answer(.failure(failure), model: &model, rig: rig)
        case 30..<40:
            drain(&model, rig)
        case 40 where model.running:
            rig.subject.stop()
            model.running = false
            model.stopQueued = true
        default:
            return
        }
    }

    private func tick(_ model: inout EffectModel) {
        guard let frame = model.latest else { return }
        model.latest = nil
        model.ticksTaking += 1
        guard model.pass == nil else {
            model.capDrops += 1
            return
        }
        model.pass = ModelPass(input: frame, index: model.passesStarted)
        model.passesStarted += 1
    }

    /// The runtime answers the running pass; its completion waits on the executor until the next drain.
    private func answer(_ result: Result<Void, EffectFailure>, model: inout EffectModel, rig: Rig) async throws {
        guard let pass = model.pass, pass.sends == nil else { return }
        let request = await rig.applyRequest(pass.index)
        #expect(request.input == pass.input)
        #expect(request.output.presentationTime == pass.input.presentationTime)
        #expect(request.frameContext == FrameContext(presentationTime: pass.input.presentationTime, frameIndex: UInt32(pass.index)))
        #expect(rig.effects.completeApply(request, with: result))
        await rig.work.finished.waitFor { $0 == pass.index }
        switch result {
        case .success:
            model.pass?.sends = request.output
            model.applied += 1
        case .failure(let failure):
            model.pass?.sends = pass.input
            model.failures[failure, default: 0] += 1
        }
    }

    /// Runs what is queued, in queue order: an answered pass's completion was queued
    /// before any `stop()` (answers happen only while running), so it runs first — into
    /// a sink that `stop()` already disconnected, if one was called — and then the
    /// stop's own work ends the slot and abandons a pass still unanswered.
    private func drain(_ model: inout EffectModel, _ rig: Rig) {
        rig.executor.drain()
        if let sends = model.pass?.sends {
            model.pass = nil
            if model.stopQueued { model.stopDrops += 1 } else { model.sent.append(sends) }
        }
        guard model.stopQueued else { return }
        model.stopQueued = false
        model.latest = nil
        if model.pass != nil {
            model.pass = nil
            model.abandoned += 1
        }
    }
}
