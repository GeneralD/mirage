import Combine
import ControlsInteractor
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("ControlsInteractorImpl", .timeLimit(.minutes(1)))
struct ControlsInteractorTests {
    // MARK: - toggleBypass

    @Test("toggleBypass takes effect before any start: it flips the bypass, sends it to the pipeline and starts no sampler")
    func toggleWithoutStart() async {
        let rig = ControlsRig()
        rig.watch()

        rig.subject.toggleBypass()
        await rig.states.waitForCount(2)

        #expect(rig.states.last == ControlsState(isBypassed: true, framesPerSecond: 0))
        #expect(rig.pipeline.bypasses.values == [true])
        #expect(rig.clock.sleepers.count == 0)
    }

    @Test("each toggleBypass flips the bypass back, and the pipeline gets the values in call order")
    func toggleFlipsBack() async {
        let rig = ControlsRig()
        rig.watch()

        rig.subject.toggleBypass()
        rig.subject.toggleBypass()
        await rig.states.waitForCount(3)

        #expect(rig.states.last == ControlsState(isBypassed: false, framesPerSecond: 0))
        #expect(rig.pipeline.bypasses.values == [true, false])
    }

    // MARK: - state

    @Test("a subscriber gets ControlsState() before any command runs")
    func initialStateFirst() {
        let rig = ControlsRig()
        rig.watch()

        #expect(rig.states.values == [ControlsState()])
    }

    // MARK: - start

    @Test("after start, each second's readout is the frames received in that second: 0 then 30 then 60 reads 30 and then 30")
    func readoutCountsFramesPerSecond() async {
        let rig = ControlsRig()
        rig.watch()

        rig.subject.start()
        await rig.clock.sleepers.waitForCount(1)
        rig.pipeline.script(stats: PipelineStats(framesReceived: 30))
        rig.clock.advance(by: .seconds(1))
        await rig.states.waitForCount(2)
        #expect(rig.states.last == ControlsState(isBypassed: false, framesPerSecond: 30))

        rig.pipeline.script(stats: PipelineStats(framesReceived: 60))
        await rig.clock.sleepers.waitForCount(2)
        rig.clock.advance(by: .seconds(1))
        await rig.states.waitForCount(3)
        #expect(rig.states.last == ControlsState(isBypassed: false, framesPerSecond: 30))
    }

    @Test("a second start keeps the first sampler: one sleep stays parked on the clock")
    func secondStartKeepsOneSampler() async {
        let rig = ControlsRig()
        rig.watch()

        rig.subject.start()
        rig.subject.start()
        await rig.clock.sleepers.waitForCount(1)
        // The sentinel: the toggle is carried out after both starts, so a second sampler would have had its turn.
        rig.subject.toggleBypass()
        await rig.states.waitForCount(2)

        #expect(rig.clock.sleepers.count == 1)
        #expect(rig.clock.parkedCount == 1)
    }

    @Test("start and stop each record one developer-log line about the readout")
    func readoutRecordsLines() async {
        let rig = ControlsRig()

        rig.subject.start()
        await rig.clock.sleepers.waitForCount(1)
        rig.subject.stop()
        await rig.log.entries.waitForCount(2)

        #expect(
            rig.log.entries.values == [
                LogEntry(.pipeline, "fps readout started"),
                LogEntry(.pipeline, "fps readout stopped"),
            ])
    }

    // MARK: - stop

    @Test("stop publishes a readout of 0 and keeps the bypass, and no sample arrives once the sampler is cancelled")
    func stopEndsReadout() async {
        let rig = ControlsRig()
        rig.watch()

        rig.subject.toggleBypass()
        await rig.states.waitForCount(2)
        rig.subject.start()
        await rig.clock.sleepers.waitForCount(1)
        rig.pipeline.script(stats: PipelineStats(framesReceived: 30))
        rig.clock.advance(by: .seconds(1))
        await rig.states.waitForCount(3)
        await rig.clock.sleepers.waitForCount(2)
        rig.subject.stop()
        await rig.states.waitForCount(4)
        await rig.clock.cancelledSleepers.waitForCount(1)
        rig.clock.advance(by: .seconds(1))
        // The sentinel: the toggle's state is the next one to arrive, so nothing came in between.
        rig.subject.toggleBypass()
        await rig.states.waitForCount(5)

        #expect(
            rig.states.values == [
                ControlsState(isBypassed: false, framesPerSecond: 0),
                ControlsState(isBypassed: true, framesPerSecond: 0),
                ControlsState(isBypassed: true, framesPerSecond: 30),
                ControlsState(isBypassed: true, framesPerSecond: 0),
                ControlsState(isBypassed: false, framesPerSecond: 0),
            ])
    }

    // MARK: - readout after a restart

    @Test("a restart counts its first readout from the restart, not from the total before stop")
    func restartCountsFromResumption() async {
        let rig = ControlsRig()
        rig.watch()

        rig.subject.start()
        await rig.clock.sleepers.waitForCount(1)
        rig.pipeline.script(stats: PipelineStats(framesReceived: 10))
        rig.clock.advance(by: .seconds(1))
        await rig.states.waitForCount(2)
        await rig.clock.sleepers.waitForCount(2)
        rig.subject.stop()
        await rig.clock.cancelledSleepers.waitForCount(1)
        await rig.states.waitForCount(3)

        // Frames that arrive while the readout is stopped are not counted by it.
        rig.pipeline.script(stats: PipelineStats(framesReceived: 40))
        rig.subject.start()
        await rig.clock.sleepers.waitForCount(3)
        rig.pipeline.script(stats: PipelineStats(framesReceived: 55))
        rig.clock.advance(by: .seconds(1))
        await rig.states.waitForCount(4)

        #expect(rig.states.last == ControlsState(isBypassed: false, framesPerSecond: 15))
    }

    @Test("a readout never goes below 0: when the frame count drops, the reading is 0")
    func dropReadsZero() async {
        let rig = ControlsRig()
        rig.watch()

        rig.subject.start()
        await rig.clock.sleepers.waitForCount(1)
        rig.pipeline.script(stats: PipelineStats(framesReceived: 50))
        rig.clock.advance(by: .seconds(1))
        await rig.states.waitForCount(2)
        await rig.clock.sleepers.waitForCount(2)
        // The pipeline was rebuilt, so its counter starts again from less than it had.
        rig.pipeline.script(stats: PipelineStats(framesReceived: 20))
        rig.clock.advance(by: .seconds(1))
        await rig.states.waitForCount(3)

        #expect(rig.states.values.map(\.framesPerSecond) == [0, 50, 0])
    }
}

/// A controls Interactor built inside `withDependencies`, over a pipeline, a clock and a log
/// the test holds. `watch()` subscribes `states` to `state` and keeps the subscription.
private final class ControlsRig {
    let pipeline: FakeFramePipelineUseCase
    let clock: GatedClock
    let log: RecordingLog
    let subject: ControlsInteractorImpl
    let states = Collector<ControlsState>()
    private var subscription: AnyCancellable?

    init() {
        let pipeline = FakeFramePipelineUseCase()
        let clock = GatedClock()
        let log = RecordingLog()
        self.pipeline = pipeline
        self.clock = clock
        self.log = log
        subject = withDependencies {
            $0.framePipelineUseCase = pipeline
            $0.continuousClock = clock
            $0.developerLog = log
            $0.settingsUseCase = FakeSettingsUseCase()
            $0.effectCatalogUseCase = FakeEffectCatalogUseCase()
        } operation: {
            ControlsInteractorImpl()
        }
    }

    func watch() {
        subscription = subject.state.sink { [states] in states.append($0) }
    }
}
