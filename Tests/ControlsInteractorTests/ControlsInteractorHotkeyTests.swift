import Combine
import ControlsInteractor
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("ControlsInteractorImpl hotkeys", .timeLimit(.minutes(1)))
struct ControlsInteractorHotkeyTests {
    // MARK: - start and stop

    @Test("start prepares the store, opens the presses, then registers the hotkeys: each call once, in that order")
    func startOpensHotkeysOnce() async {
        let rig = HotkeyRig()

        rig.subject.start()
        await rig.settings.applications.waitForCount(1)

        #expect(rig.settings.calls.values == ["prepareStore", "hotkeyPresses", "applyHotkeys"])
        #expect(rig.settings.streamRequests.count == 1)
    }

    @Test("a second start does not open the presses again: one stream is requested, and a toggle after both starts is carried out once")
    func secondStartKeepsOneStream() async {
        let rig = HotkeyRig()
        rig.watch()

        rig.subject.start()
        await rig.settings.applications.waitForCount(1)
        rig.subject.start()
        // The sentinel: the toggle is carried out after both starts, so a second listener would have had its turn.
        rig.subject.toggleBypass()
        await rig.states.waitForCount(2)

        #expect(rig.settings.streamRequests.count == 1)
        #expect(rig.settings.calls.values == ["prepareStore", "hotkeyPresses", "applyHotkeys"])
    }

    @Test("a press that comes after stop does nothing: after a restart, the catalog gets only the press made after it")
    func pressAfterStopDoesNothing() async {
        let rig = HotkeyRig()

        rig.subject.start()
        await rig.settings.applications.waitForCount(1)
        rig.subject.stop()
        await rig.developerLog.entries.waitForCount(2)
        // Sent once the stop is carried out: the listener is gone, so the press reaches nobody.
        rig.settings.press(.nextEffect)
        rig.subject.start()
        await rig.settings.applications.waitForCount(2)
        // The sentinel: the press made after the restart is the only one the catalog gets.
        rig.settings.press(.previousEffect)
        await rig.catalog.adjacentSteps.waitForCount(1)

        #expect(rig.catalog.adjacentSteps.values == [.previous])
    }

    // MARK: - presses

    @Test("a press of the bypass hotkey flips the bypass as toggleBypass does, and sends it to the pipeline")
    func bypassPressFlipsBypass() async {
        let rig = HotkeyRig()
        rig.watch()

        rig.subject.start()
        await rig.settings.applications.waitForCount(1)
        rig.settings.press(.toggleBypass)
        await rig.states.waitForCount(2)

        #expect(rig.states.last == ControlsState(isBypassed: true, framesPerSecond: 0))
        #expect(rig.pipeline.bypasses.values == [true])
    }

    @Test("a next press asks the catalog for the next effect, and a previous press for the previous one, in press order")
    func adjacentPressesAskCatalog() async {
        let rig = HotkeyRig()

        rig.subject.start()
        await rig.settings.applications.waitForCount(1)
        rig.settings.press(.nextEffect)
        await rig.catalog.adjacentSteps.waitForCount(1)
        rig.settings.press(.previousEffect)
        await rig.catalog.adjacentSteps.waitForCount(2)

        #expect(rig.catalog.adjacentSteps.values == [.next, .previous])
    }

    // MARK: - the outcome of a switch

    @Test("a switch that prepares its effect is logged as one developer line: hotkey next effect: prepared")
    func preparedSwitchLogsDeveloperLine() async {
        let rig = HotkeyRig()

        rig.subject.start()
        await rig.settings.applications.waitForCount(1)
        rig.settings.press(.nextEffect)
        await rig.developerLog.entries.waitForCount(2)

        #expect(
            rig.developerLog.entries.values == [
                LogEntry(.pipeline, "fps readout started"),
                LogEntry(.effect, "hotkey next effect: prepared"),
            ])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("a switch with no neighbour to go to is logged as one developer line: nothing to switch to")
    func noNeighbourLogsDeveloperLine() async {
        let rig = HotkeyRig()
        rig.catalog.script(adjacentOutcome: nil)

        rig.subject.start()
        await rig.settings.applications.waitForCount(1)
        rig.settings.press(.previousEffect)
        await rig.developerLog.entries.waitForCount(2)

        #expect(rig.developerLog.entries.last == LogEntry(.effect, "hotkey previous effect: nothing to switch to"))
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("a switch whose effect fails to compile is logged as one error line that says failed (")
    func failedSwitchLogsErrorLine() async {
        let rig = HotkeyRig()
        rig.catalog.script(adjacentOutcome: .failed(.compileFailed))

        rig.subject.start()
        await rig.settings.applications.waitForCount(1)
        rig.settings.press(.nextEffect)
        await rig.errorLog.entries.waitForCount(1)

        #expect(rig.errorLog.entries.values == [LogEntry(.effect, "hotkey next effect: failed (compileFailed)")])
    }
}

/// A controls Interactor built inside `withDependencies`, over the settings and the catalog the
/// test holds, a pipeline, a clock, and two logs: one for the developer sink and one for the error
/// sink, so a test can tell which sink got a line. `watch()` subscribes `states` to `state` and
/// keeps the subscription.
private final class HotkeyRig {
    let pipeline: FakeFramePipelineUseCase
    let settings: FakeSettingsUseCase
    let catalog: FakeEffectCatalogUseCase
    let developerLog: RecordingLog
    let errorLog: RecordingLog
    let subject: ControlsInteractorImpl
    let states = Collector<ControlsState>()
    private var subscription: AnyCancellable?

    init() {
        let pipeline = FakeFramePipelineUseCase()
        let settings = FakeSettingsUseCase()
        let catalog = FakeEffectCatalogUseCase()
        let developerLog = RecordingLog()
        let errorLog = RecordingLog()
        self.pipeline = pipeline
        self.settings = settings
        self.catalog = catalog
        self.developerLog = developerLog
        self.errorLog = errorLog
        subject = withDependencies {
            $0.framePipelineUseCase = pipeline
            $0.continuousClock = GatedClock()
            $0.settingsUseCase = settings
            $0.effectCatalogUseCase = catalog
            $0.developerLog = developerLog
            $0.errorLog = errorLog
        } operation: {
            ControlsInteractorImpl()
        }
    }

    func watch() {
        subscription = subject.state.sink { [states] in states.append($0) }
    }
}
