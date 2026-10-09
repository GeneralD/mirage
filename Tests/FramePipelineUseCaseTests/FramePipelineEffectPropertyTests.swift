import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

/// A pass the model knows is in flight: its input, the order it started in (which is
/// also its `apply` request and its work item, as nothing else starts work here), the
/// frame index its run handed it and — once the runtime has answered — the answer and
/// the frame it would send. `stop` abandons it, but it stays in flight until answered.
private struct ModelPass {
    let input: FrameRef
    let index: Int
    let frameIndex: UInt32
    var answer: Result<Void, EffectFailure>?
    var sends: FrameRef?
    var abandoned = false
}

/// Executor work that waits for the next drain, in the order it was queued.
private enum Queued: Equatable {
    /// A pass's answer, hopping back onto the executor.
    case answer
    /// The second half of `stop()`: the slot ends and the pass is abandoned.
    case stop
}

/// What the test expects the subject to have done, tracked independently of it.
private struct EffectModel {
    var running = true
    /// From `start` until the next `stop()` call, which disconnects at once.
    var sinkConnected = true
    var queue: [Queued] = []
    var latest: FrameRef?
    var pass: ModelPass?
    var passesStarted = 0
    /// Passes started in this run: the next pass's frame index.
    var runPasses: UInt32 = 0
    var emitted = 0
    /// Ticks that found a frame in the slot: each ends in exactly one send, one drop,
    /// or (at stop) one abandoned pass.
    var ticksTaking = 0
    var sent: [FrameRef] = []
    var capDrops = 0
    /// Cap drops in a restarted run while the old run's abandoned pass still held the cap.
    var capDropsBehindAbandoned = 0
    /// Answers drained after `stop()` disconnected the sink: their frame drops as `.notConnected`.
    var stopDrops = 0
    var abandoned = 0
    var abandonedAnswered = 0
    var restarts = 0
    var applied = 0
    var failures: [EffectFailure: Int] = [:]

    /// The leases the pipeline holds: the slot's frame, and a pass's input and output
    /// (an abandoned pass's too, until its answer).
    var live: Int { (latest == nil ? 0 : 1) + (pass == nil ? 0 : 2) }
    var stopQueued: Bool { queue.contains(.stop) }
}

/// Which paths a run took, so the suite can prove the seeds reach all of them.
private struct EffectCoverage {
    var capDrops = 0
    var applied = 0
    var failed = 0
    var abandoned = 0
    var stopDrops = 0
    var restarts = 0
    var capDropsBehindAbandoned = 0
}

@Suite("FramePipelineUseCaseImpl effect stage properties", .timeLimit(.minutes(1)))
struct FramePipelineEffectPropertyTests {
    @Test(
        "any order of capture, tick, answer, failure, drain, stop and restart keeps every lease balanced, the stream in order and every taken frame accounted for",
        arguments: Seeds.range(0..<50))
    func invariantsHold(seed: UInt64) async throws {
        _ = try await run(seed: seed)
    }

    @Test(
        "across the seeds every path is taken: applied, failed, cap drop, abandoned at stop, answered into a stopping sink, restart behind an abandoned pass"
    )
    func seedsCoverEveryPath() async throws {
        var total = EffectCoverage()
        for seed in Seeds.range(0..<50) {
            let coverage = try await run(seed: seed)
            total.capDrops += coverage.capDrops
            total.applied += coverage.applied
            total.failed += coverage.failed
            total.abandoned += coverage.abandoned
            total.stopDrops += coverage.stopDrops
            total.restarts += coverage.restarts
            total.capDropsBehindAbandoned += coverage.capDropsBehindAbandoned
        }
        #expect(total.capDrops > 0, "no seed ever hit the in-flight cap")
        #expect(total.applied > 0, "no seed ever applied an effect")
        #expect(total.failed > 0, "no seed ever passed a failure through")
        #expect(total.abandoned > 0, "no seed ever stopped with a pass in flight")
        #expect(total.stopDrops > 0, "no seed ever drained an answer after stop")
        #expect(total.restarts > 0, "no seed ever restarted")
        #expect(total.capDropsBehindAbandoned > 0, "no seed ever ticked a restarted run into an abandoned pass")
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

        // Close the run: stop, run what is queued, then answer a pass still on the GPU —
        // its leases end with that answer and nothing earlier.
        if model.running { try await step(40, at: time, model: &model, rig: rig, generator: &generator) }
        drain(&model, rig)
        try await answer(.failure(.timeout), model: &model, rig: rig)
        drain(&model, rig)
        await rig.work.finished.waitForCount(rig.work.started.count)
        rig.executor.drain()

        let stats = rig.subject.stats
        #expect(rig.effects.pendingCount == 0, "seed \(seed)")
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
        #expect(model.abandonedAnswered == model.abandoned, "seed \(seed): every abandoned pass was answered and ended")
        #expect(stats.effectsApplied == model.applied, "seed \(seed): an abandoned pass is not counted")
        #expect(stats.effectFailures == model.failures, "seed \(seed)")
        return EffectCoverage(
            capDrops: model.capDrops, applied: model.applied, failed: model.failures.values.reduce(0, +),
            abandoned: model.abandoned, stopDrops: model.stopDrops, restarts: model.restarts,
            capDropsBehindAbandoned: model.capDropsBehindAbandoned)
    }

    /// `roll` in 0..<41 picks the step; stop is rare (40) so most runs do real work first.
    /// While stopped (and the stop has run), the capture and tick rolls restart instead,
    /// and an abandoned pass is answered by only a few of the answer rolls.
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
        case 0..<16 where !model.running && !model.stopQueued:
            try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
            model.running = true
            model.sinkConnected = true
            model.runPasses = 0
            model.restarts += 1
            drain(&model, rig)
        case 19..<30 where model.pass?.abandoned == true:
            // Most answer rolls hold an abandoned pass back, as a slow GPU would, so a
            // restarted run gets to tick into it.
            return
        case 16..<24:
            try await answer(.success(()), model: &model, rig: rig)
        case 24..<30:
            let failure = everyEffectFailure[Int.random(in: 0..<everyEffectFailure.count, using: &generator)]
            try await answer(.failure(failure), model: &model, rig: rig)
        case 30..<40:
            drain(&model, rig)
        case 40 where model.running:
            rig.subject.stop()
            model.running = false
            model.sinkConnected = false
            model.queue.append(.stop)
        default:
            return
        }
    }

    private func tick(_ model: inout EffectModel) {
        guard let frame = model.latest else { return }
        model.latest = nil
        model.ticksTaking += 1
        if let pass = model.pass {
            model.capDrops += 1
            if pass.abandoned { model.capDropsBehindAbandoned += 1 }
            return
        }
        model.pass = ModelPass(input: frame, index: model.passesStarted, frameIndex: model.runPasses)
        model.passesStarted += 1
        model.runPasses += 1
    }

    /// The runtime answers the pass in flight, abandoned or not; the answer waits on the
    /// executor until the next drain.
    private func answer(_ result: Result<Void, EffectFailure>, model: inout EffectModel, rig: Rig) async throws {
        guard let pass = model.pass, pass.answer == nil else { return }
        let request = await rig.applyRequest(pass.index)
        #expect(request.input == pass.input)
        #expect(request.output.presentationTime == pass.input.presentationTime)
        #expect(request.frameContext == FrameContext(presentationTime: pass.input.presentationTime, frameIndex: pass.frameIndex))
        #expect(rig.effects.completeApply(request, with: result), "the call is still pending: nothing answered it but the test")
        await rig.work.finished.waitFor { $0 == pass.index }
        model.pass?.answer = result
        model.pass?.sends = (try? result.get()).map { request.output } ?? pass.input
        model.queue.append(.answer)
    }

    /// Runs what is queued, in queue order. An answer queued before `stop()` finishes its
    /// pass normally — into a sink `stop()` already disconnected; the stop's own work then
    /// ends the slot and abandons a pass still unanswered, whose later answer only ends
    /// its leases.
    private func drain(_ model: inout EffectModel, _ rig: Rig) {
        rig.executor.drain()
        for queued in model.queue {
            switch queued {
            case .answer: finish(&model)
            case .stop: abandon(&model)
            }
        }
        model.queue = []
    }

    private func finish(_ model: inout EffectModel) {
        guard let pass = model.pass, let result = pass.answer, let sends = pass.sends else { return }
        model.pass = nil
        guard !pass.abandoned else {
            model.abandonedAnswered += 1
            return
        }
        switch result {
        case .success: model.applied += 1
        case .failure(let failure): model.failures[failure, default: 0] += 1
        }
        if model.sinkConnected { model.sent.append(sends) } else { model.stopDrops += 1 }
    }

    private func abandon(_ model: inout EffectModel) {
        model.latest = nil
        guard model.pass != nil else { return }
        model.pass?.abandoned = true
        model.abandoned += 1
    }
}
