import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

/// The pool the property runs on, the size D9 fixes for the pipeline's tests: the slot's
/// frame, a pass's two leases and one frame on the preview fill it, so a preview that lags
/// makes the camera and the output lease meet a full pool, and the run has to account for
/// both.
private let capacity = 4

/// A pass the model knows is in flight: its input, its start order (its `apply` request
/// and its work item), and once answered the answer and the frame it would send.
private struct ModelPass {
    let input: FrameRef
    let index: Int
    var answer: Result<Void, EffectFailure>?
    var sends: FrameRef?
    var abandoned = false
}

/// Executor work the model orders; a preview completion's hop needs no slot here, since
/// the next drain runs it whatever it is queued behind.
private enum Queued: Equatable {
    case answer
    case stop
}

/// What the test expects the subject to have done, tracked independently of it.
private struct PreviewModel {
    var running = true
    /// Which run is current; a frame on the preview remembers the run that showed it.
    var run = 0
    var attached = false
    var queue: [Queued] = []
    var latest: FrameRef?
    var pass: ModelPass?
    var passesStarted = 0
    var emitted = 0
    var ticksTaking = 0
    var sent: [FrameRef] = []
    var capDrops = 0
    var poolDrops = 0
    var abandoned = 0
    var applied = 0
    var failed = 0
    /// Frames on the preview, in presentation order (the fake's `pending` order), by the
    /// run that showed them; each holds its lease.
    var showing: [Int] = []
    /// Completions the test gave whose hop onto the executor has not run yet; their
    /// leases are still live until the next drain.
    var completing = 0

    // What the run went through, for the coverage test.
    var refusedEmits = 0
    var shownAtOnce = 0
    var held = 0
    var completedOutOfOrder = 0
    var stopsWithFrameOnPreview = 0
    var completionsAfterRestart = 0
    var restarts = 0

    var live: Int { (latest == nil ? 0 : 1) + (pass == nil ? 0 : 2) + showing.count + completing }
    var stopQueued: Bool { queue.contains(.stop) }
}

private struct PreviewCoverage {
    var applied = 0
    var failed = 0
    var capDrops = 0
    var poolDrops = 0
    var refusedEmits = 0
    var abandoned = 0
    var shownAtOnce = 0
    var held = 0
    var completedOutOfOrder = 0
    var stopsWithFrameOnPreview = 0
    var completionsAfterRestart = 0

    mutating func add(_ model: PreviewModel) {
        applied += model.applied
        failed += model.failed
        capDrops += model.capDrops
        poolDrops += model.poolDrops
        refusedEmits += model.refusedEmits
        abandoned += model.abandoned
        shownAtOnce += model.shownAtOnce
        held += model.held
        completedOutOfOrder += model.completedOutOfOrder
        stopsWithFrameOnPreview += model.stopsWithFrameOnPreview
        completionsAfterRestart += model.completionsAfterRestart
    }
}

@Suite("FramePipelineUseCaseImpl preview fan-out properties", .timeLimit(.minutes(1)))
struct FramePipelinePreviewPropertyTests {
    @Test(
        "any order of emit, tick, effect answer, send, preview completion, attach, stop and restart keeps every lease balanced, shows every sent frame and accounts for every taken one",
        arguments: Seeds.range(0..<50))
    func invariantsHold(seed: UInt64) async throws {
        _ = try await run(seed: seed)
    }

    @Test(
        "across the seeds every path is taken: shown at once and held, completed out of order, stopped and completed after a restart with a frame on the preview, a full pool"
    )
    func seedsCoverEveryPath() async throws {
        var total = PreviewCoverage()
        for seed in Seeds.range(0..<50) {
            total.add(try await run(seed: seed))
        }
        #expect(total.applied > 0, "no seed ever applied an effect")
        #expect(total.failed > 0, "no seed ever passed a failure through")
        #expect(total.capDrops > 0, "no seed ever hit the in-flight cap")
        #expect(total.poolDrops > 0, "no seed ever filled the pool before an output lease")
        #expect(total.refusedEmits > 0, "no seed ever filled the pool before a camera frame")
        #expect(total.abandoned > 0, "no seed ever stopped with a pass in flight")
        #expect(total.shownAtOnce > 0, "no seed ever showed a frame before the preview was attached")
        #expect(total.held > 0, "no seed ever showed a frame on an attached preview")
        #expect(total.completedOutOfOrder > 0, "no seed ever completed a later frame first")
        #expect(total.stopsWithFrameOnPreview > 0, "no seed ever stopped with a frame on the preview")
        #expect(total.completionsAfterRestart > 0, "no seed ever completed an earlier run's frame after a restart")
    }

    private func run(seed: UInt64) async throws -> PreviewModel {
        var generator = SeededGenerator(seed: seed)
        let rig = Rig(capacity: capacity)
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        // Mutable: advanced once per step; it is the oracle the subject is judged against.
        var model = PreviewModel()
        var time: UInt64 = 1_000_000

        for _ in 0..<80 {
            time += UInt64.random(in: 1...40_000_000, using: &generator)
            try await step(Int.random(in: 0..<49, using: &generator), at: time, model: &model, rig: rig, generator: &generator)
            #expect(rig.surfaces.liveCount == model.live, "seed \(seed): the pipeline holds exactly the slot, the pass and the frames on the preview")
            #expect(rig.surfaces.refusedReleases == 0, "seed \(seed): no lease released twice")
            #expect(rig.preview.pending.count == model.showing.count, "seed \(seed)")
        }

        // Close the run: stop, answer a pass still on the GPU, complete what the preview
        // still shows, in any order — every lease ends with the last of them, and none earlier.
        if model.running { try await step(48, at: time, model: &model, rig: rig, generator: &generator) }
        drain(&model, rig)
        try await answer(.failure(.timeout), model: &model, rig: rig)
        drain(&model, rig)
        while !model.showing.isEmpty {
            try completePresentation(model: &model, rig: rig, generator: &generator)
        }
        drain(&model, rig)
        await rig.work.finished.waitForCount(rig.work.started.count)
        rig.executor.drain()

        let stats = rig.subject.stats
        #expect(rig.effects.pendingCount == 0, "seed \(seed)")
        #expect(rig.preview.pending.isEmpty, "seed \(seed)")
        #expect(rig.surfaces.liveCount == 0, "seed \(seed)")
        #expect(rig.surfaces.refusedReleases == 0, "seed \(seed)")
        #expect(rig.sink.sent.values == model.sent, "seed \(seed): success sends the output, any failure the input itself")
        #expect(rig.preview.presented.values.map(\.frame) == model.sent, "seed \(seed): every frame sent is shown once, in the same order")
        let times = rig.sink.sent.values.map(\.presentationTime)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 }, "seed \(seed): PTS strictly increasing")
        #expect(stats.framesReceived == model.emitted, "seed \(seed)")
        #expect(stats.framesSent == model.sent.count, "seed \(seed)")
        #expect(stats.framesDropped == model.capDrops + model.poolDrops, "seed \(seed)")
        var reasons: [FrameDropReason: Int] = [:]
        if model.capDrops > 0 { reasons[.inFlightCapReached] = model.capDrops }
        if model.poolDrops > 0 { reasons[.poolExhausted] = model.poolDrops }
        #expect(stats.dropReasons == reasons, "seed \(seed)")
        #expect(
            model.ticksTaking == stats.framesSent + stats.framesDropped + model.abandoned,
            "seed \(seed): every frame a tick took was sent, counted as a drop, or abandoned by stop — the preview changes none of it")
        #expect(stats.effectsApplied == model.applied, "seed \(seed)")
        #expect(stats.effectsFailed == model.failed, "seed \(seed)")
        return model
    }

    /// `roll` in 0..<49 picks the step; stop (48) is rare so most runs do real work
    /// first. A preview completion is rarer than a send, so frames pile up on the preview
    /// and the pool fills. While stopped (and the stop has run), the emit and tick rolls
    /// restart instead, and an abandoned pass is answered by only a few of the answer rolls.
    private func step(
        _ roll: Int, at time: UInt64, model: inout PreviewModel, rig: Rig, generator: inout SeededGenerator
    ) async throws {
        switch roll {
        case 0..<8 where model.running:
            emit(at: time, model: &model, rig: rig)
        case 8..<16 where model.running:
            rig.scheduler.tick()
            tick(&model)
            #expect(rig.work.started.count == model.passesStarted)
        case 0..<16 where !model.running && !model.stopQueued:
            try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
            model.running = true
            model.run += 1
            model.restarts += 1
            drain(&model, rig)
        case 19..<30 where model.pass?.abandoned == true:
            // Most answer rolls hold an abandoned pass back, as a slow GPU would.
            return
        case 16..<24:
            try await answer(.success(()), model: &model, rig: rig)
        case 24..<30:
            let failure = everyEffectFailure[Int.random(in: 0..<everyEffectFailure.count, using: &generator)]
            try await answer(.failure(failure), model: &model, rig: rig)
        case 30..<38, 42..<46:
            drain(&model, rig)
        case 38..<42 where !model.showing.isEmpty:
            try completePresentation(model: &model, rig: rig, generator: &generator)
        case 46..<48 where !model.attached:
            try rig.attachPreview()
            model.attached = true
        case 48 where model.running:
            rig.subject.stop()
            model.running = false
            if !model.showing.isEmpty || model.completing > 0 { model.stopsWithFrameOnPreview += 1 }
            abandon(&model)
            model.queue.append(.stop)
        default:
            return
        }
    }

    /// The camera leases its surface from the same pool: with every slot taken it is refused.
    private func emit(at time: UInt64, model: inout PreviewModel, rig: Rig) {
        let frame = rig.emit(at: time)
        guard model.live < capacity else {
            #expect(frame == nil, "a full pool refuses the camera")
            model.refusedEmits += 1
            return
        }
        #expect(frame != nil, "a pool with a free slot never refuses the camera")
        model.emitted += 1
        model.latest = frame
    }

    /// A tick takes the slot's frame; with a pass running it drops it, otherwise it leases
    /// the output from the pool — refused when the pool is full, which drops the frame too.
    private func tick(_ model: inout PreviewModel) {
        guard let frame = model.latest else { return }
        model.ticksTaking += 1
        guard model.pass == nil else {
            model.latest = nil
            model.capDrops += 1
            return
        }
        // The input still holds its surface while the output is leased.
        guard model.live < capacity else {
            model.latest = nil
            model.poolDrops += 1
            return
        }
        model.latest = nil
        model.pass = ModelPass(input: frame, index: model.passesStarted)
        model.passesStarted += 1
    }

    /// The runtime answers the pass in flight, abandoned or not; the answer waits on the
    /// executor until the next drain.
    private func answer(_ result: Result<Void, EffectFailure>, model: inout PreviewModel, rig: Rig) async throws {
        guard let pass = model.pass, pass.answer == nil else { return }
        let request = try await rig.applyRequest(pass.index)
        #expect(request.input == pass.input)
        #expect(rig.effects.completeApply(request, with: result))
        await rig.work.finished.waitFor { $0 == pass.index }
        model.pass?.answer = result
        model.pass?.sends = (try? result.get()).map { request.output } ?? pass.input
        model.queue.append(.answer)
    }

    /// The preview completes one of the frames it shows, any of them; the completion hops
    /// onto the executor, so the lease is still live until the next drain.
    private func completePresentation(model: inout PreviewModel, rig: Rig, generator: inout SeededGenerator) throws {
        let pending = rig.preview.pending
        try #require(pending.count == model.showing.count)
        let index = Int.random(in: 0..<pending.count, using: &generator)
        #expect(rig.preview.complete(pending[index]))
        if index > 0 { model.completedOutOfOrder += 1 }
        if model.showing.remove(at: index) < model.run { model.completionsAfterRestart += 1 }
        model.completing += 1
    }

    private func abandon(_ model: inout PreviewModel) {
        guard let pass = model.pass, !pass.abandoned else { return }
        model.pass?.abandoned = true
        model.abandoned += 1
    }

    /// Runs what is queued, in queue order: an answer ends its pass (sent and shown, or for
    /// an abandoned pass only its leases ended); the stop's cleanup ends the slot; every
    /// completion's hop ends its frame's lease.
    private func drain(_ model: inout PreviewModel, _ rig: Rig) {
        rig.executor.drain()
        for queued in model.queue {
            switch queued {
            case .answer: finish(&model)
            case .stop: model.latest = nil
            }
        }
        model.queue = []
        model.completing = 0
    }

    private func finish(_ model: inout PreviewModel) {
        guard let pass = model.pass, let result = pass.answer, let sends = pass.sends else { return }
        model.pass = nil
        guard !pass.abandoned else { return }
        switch result {
        case .success: model.applied += 1
        case .failure: model.failed += 1
        }
        model.sent.append(sends)
        // Before an attach the preview completes inside `present`, and the hop runs in this drain.
        guard model.attached else {
            model.shownAtOnce += 1
            return
        }
        model.showing.append(model.run)
        model.held += 1
    }
}
