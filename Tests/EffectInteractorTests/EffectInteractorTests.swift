import Combine
import Dependencies
import Domain
import EffectInteractor
import TestDoubles
import TestSupport
import Testing

@Suite("EffectInteractorImpl", .timeLimit(.minutes(1)))
struct EffectInteractorTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let glitch = EffectCatalogEntry.fixture(.package("glitch"), displayName: "Glitch")

    // MARK: - start / stop

    @Test("start runs the catalog, once, and stop cancels that run")
    func startRunsAndStopCancels() async {
        let rig = InteractorRig()

        rig.subject.start()
        await rig.catalog.runs.waitForCount(1)
        #expect(rig.catalog.runCancellations.count == 0)

        rig.subject.stop()
        await rig.catalog.runCancellations.waitForCount(1)
        #expect(rig.catalog.runs.count == 1)
    }

    @Test("a second start ends the first run before the next begins, so one run stays alive")
    func restartKeepsOneRun() async {
        let rig = InteractorRig()

        rig.subject.start()
        await rig.catalog.runs.waitForCount(1)
        rig.subject.start()
        await rig.catalog.runs.waitForCount(2)

        #expect(rig.catalog.runCancellations.count == 1, "the first run was cancelled before the second began")
        await rig.catalog.observations.waitForCount(2)
        await rig.catalog.observationTerminations.waitForCount(1)

        rig.subject.stop()
        await rig.catalog.runCancellations.waitForCount(2)
    }

    @Test("a second start waits for the run it ends to return before it begins the next: the two never overlap")
    func restartWaitsForTheRunItEnds() async {
        // Whether a new run overtakes one that is still returning depends on how the pool
        // schedules the two tasks, and a test cannot wait for something that must not happen.
        // An Interactor that does not wait for the old run therefore fails some rounds and not
        // others (about 19 in 20 with the wait removed), so the rounds are many enough that it
        // fails one. One that waits fails none: the order below is the only one it can produce.
        for _ in 0..<20 {
            let rig = InteractorRig()
            rig.catalog.holdCancelledRuns()

            rig.subject.start()
            await rig.catalog.runs.waitForCount(1)
            rig.subject.start()
            await rig.catalog.runCancellations.waitForCount(1)
            rig.catalog.releaseCancelledRuns()
            await rig.catalog.runs.waitForCount(2)

            #expect(rig.catalog.runEvents.values == [.started(1), .ended(1), .started(2)])

            rig.subject.stop()
            await rig.catalog.runCancellations.waitForCount(2)
        }
    }

    @Test("stop before any start runs nothing, and a start after it still runs the catalog once")
    func stopBeforeStart() async {
        let rig = InteractorRig()

        rig.subject.stop()
        rig.subject.start()
        await rig.catalog.runs.waitForCount(1)

        #expect(rig.catalog.runCancellations.count == 0)
        #expect(rig.catalog.runs.count == 1)
    }

    @Test("start and stop queued back to back are carried out in that order: the run is started and then ended")
    func commandsKeepTheirOrder() async {
        let rig = InteractorRig()

        rig.subject.start()
        rig.subject.stop()
        rig.subject.start()
        rig.subject.stop()
        await rig.catalog.runCancellations.waitForCount(2)

        #expect(rig.catalog.runs.count == 2)
    }

    @Test("an Interactor that is let go ends the run it owned")
    func releaseEndsTheRun() async {
        let catalog = FakeEffectCatalogUseCase()
        var subject: EffectInteractorImpl? = InteractorRig.make(catalog: catalog, errorLog: RecordingLog(), developerLog: RecordingLog())

        subject?.start()
        await catalog.runs.waitForCount(1)
        subject = nil

        await catalog.runCancellations.waitForCount(1)
        await catalog.observationTerminations.waitForCount(1)
    }

    // MARK: - state

    @Test("state publishes nothing before start, even when the catalog already has a state")
    func nothingBeforeStart() {
        let rig = InteractorRig(state: .fixture([chromatic]))
        let seen = Collector<EffectCatalogState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        #expect(seen.count == 0)
        #expect(rig.catalog.observations.count == 0, "nothing observes the catalog until start")
        withExtendedLifetime(subscription) {}
    }

    @Test("after start state publishes the catalog's current state first, then each change")
    func publishesCurrentThenChanges() async {
        let first = EffectCatalogState.fixture([chromatic])
        let second = EffectCatalogState.fixture([chromatic, glitch], outcome: .prepared)
        let rig = InteractorRig(state: first)
        let seen = Collector<EffectCatalogState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        rig.subject.start()
        await seen.waitForCount(1)
        rig.catalog.publish(second)
        await seen.waitForCount(2)

        #expect(seen.values == [first, second])
        withExtendedLifetime(subscription) {}
    }

    @Test("a subscriber that arrives while it runs starts from the latest state")
    func lateSubscriberStartsFromLatest() async {
        let latest = EffectCatalogState.fixture([chromatic, glitch])
        let rig = InteractorRig(state: .fixture([chromatic]))
        let early = Collector<EffectCatalogState>()
        let earlySubscription = rig.subject.state.sink { early.append($0) }

        rig.subject.start()
        await early.waitForCount(1)
        rig.catalog.publish(latest)
        await early.waitForCount(2)

        let late = Collector<EffectCatalogState>()
        let lateSubscription = rig.subject.state.sink { late.append($0) }
        #expect(late.values == [latest])
        withExtendedLifetime([earlySubscription, lateSubscription]) {}
    }

    @Test("after stop the catalog's changes no longer reach state, and a later start begins again from the current one")
    func nothingAfterStop() async {
        let first = EffectCatalogState.fixture([chromatic])
        let unseen = EffectCatalogState.fixture([chromatic, glitch])
        let rig = InteractorRig(state: first)
        let seen = Collector<EffectCatalogState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        rig.subject.start()
        await seen.waitForCount(1)
        rig.subject.stop()
        await rig.catalog.observationTerminations.waitForCount(1)
        await rig.catalog.runEvents.waitForCount(2)  // the run has returned, and with it everything it had made current
        rig.catalog.publish(unseen)
        #expect(seen.values == [first], "the stream was gone before the change, so the stopped Interactor forwarded nothing")

        rig.subject.start()
        await seen.waitForCount(2)
        #expect(seen.values == [first, unseen], "the restart began from the catalog's current state, once")
        withExtendedLifetime(subscription) {}
    }

    @Test("a restart forwards each change once: the first run's observation is gone")
    func restartForwardsOnce() async {
        let first = EffectCatalogState.fixture([chromatic])
        let second = EffectCatalogState.fixture([chromatic, glitch])
        let third = EffectCatalogState.fixture([glitch, chromatic])
        let rig = InteractorRig(state: first)
        let seen = Collector<EffectCatalogState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        rig.subject.start()
        await seen.waitForCount(1)
        rig.subject.start()
        await rig.catalog.observations.waitForCount(2)  // the second run observes; the first run's end left nothing current
        rig.catalog.publish(first)  // the second run's own first state
        await seen.waitForCount(2)
        rig.catalog.publish(second)
        rig.catalog.publish(third)
        await seen.waitForCount(4)

        #expect(seen.values == [first, first, second, third])
        withExtendedLifetime(subscription) {}
    }

    // MARK: - select / openEffectsFolder

    @Test("select reaches the catalog, and a prepared effect is a developer-log line only")
    func selectPrepared() async {
        let rig = InteractorRig(selectOutcome: .prepared)

        rig.subject.select(.package("glitch"))
        await rig.developerLog.entries.waitForCount(1)

        #expect(rig.catalog.selections.values == [.package("glitch")])
        #expect(rig.developerLog.entries.values == [LogEntry(.effect, "select package/glitch: prepared")])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("a select that did not run the effect is an error-log line only, naming why")
    func selectNotRunning() async {
        let cases: [(EffectSelectionOutcome, String)] = [
            (.failed(.compileFailed), "select bundled/Chromatic Grain: failed (compileFailed)"),
            (.unavailable(.sourceMissing), "select bundled/Chromatic Grain: unavailable (sourceMissing)"),
            (.unavailable(nil), "select bundled/Chromatic Grain: unavailable (not in the catalog)"),
        ]
        for (outcome, line) in cases {
            let rig = InteractorRig(selectOutcome: outcome)

            rig.subject.select(.bundled("Chromatic Grain"))
            await rig.errorLog.entries.waitForCount(1)

            #expect(rig.errorLog.entries.values == [LogEntry(.effect, line)])
            #expect(rig.developerLog.entries.count == 0)
        }
    }

    @Test("select does not need the Interactor to be started, and each call is answered on its own")
    func selectWithoutStart() async {
        let rig = InteractorRig(selectOutcome: .prepared)

        rig.subject.select(.package("a"))
        rig.subject.select(.package("b"))
        await rig.developerLog.entries.waitForCount(2)

        // A set, by design: a choice is its own task and the port promises no order between two of them.
        #expect(Set(rig.catalog.selections.values) == [.package("a"), .package("b")])
        #expect(rig.catalog.runs.count == 0)
    }

    @Test("openEffectsFolder is the catalog's, once per call")
    func openEffectsFolder() {
        let rig = InteractorRig()

        rig.subject.openEffectsFolder()
        rig.subject.openEffectsFolder()

        #expect(rig.catalog.folderOpens.count == 2)
    }
}

/// An Interactor over a `FakeEffectCatalogUseCase`, built inside `withDependencies`
/// (the subject captures the dependencies of the scope it is made in).
private struct InteractorRig {
    let catalog: FakeEffectCatalogUseCase
    let errorLog = RecordingLog()
    let developerLog = RecordingLog()
    let subject: EffectInteractorImpl

    init(state: EffectCatalogState? = nil, selectOutcome: EffectSelectionOutcome = .prepared) {
        catalog = FakeEffectCatalogUseCase(state: state, selectOutcome: selectOutcome)
        subject = Self.make(catalog: catalog, errorLog: errorLog, developerLog: developerLog)
    }

    static func make(catalog: FakeEffectCatalogUseCase, errorLog: RecordingLog, developerLog: RecordingLog) -> EffectInteractorImpl {
        withDependencies {
            $0.effectCatalogUseCase = catalog
            $0.errorLog = errorLog
            $0.developerLog = developerLog
        } operation: {
            EffectInteractorImpl()
        }
    }
}
