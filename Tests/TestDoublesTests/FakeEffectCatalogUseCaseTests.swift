import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectCatalogUseCase", .timeLimit(.minutes(1)))
struct FakeEffectCatalogUseCaseTests {
    private let glitch = EffectCatalogEntry.fixture(.package("glitch"))
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    @MainActor
    @Test("run does not return until its task is cancelled, and then records the cancel")
    func runUntilCancelled() async {
        let useCase = FakeEffectCatalogUseCase()
        let returned = Collector<Void>()
        let task = Task {
            await useCase.run()
            returned.append(())
        }
        await useCase.runs.waitForCount(1)

        let returnedEarly = await tickUntil(50, tick: {}, until: { returned.count > 0 })
        #expect(!returnedEarly, "run() is a long-lived task: it ends when it is cancelled, not before")
        #expect(useCase.runCancellations.count == 0)

        task.cancel()
        await returned.waitForCount(1)
        #expect(useCase.runCancellations.count == 1)
    }

    @Test("runEvents record when each run began and returned, in one order")
    func runEventsAreInOrder() async {
        let useCase = FakeEffectCatalogUseCase()

        let first = Task { await useCase.run() }
        await useCase.runs.waitForCount(1)
        first.cancel()
        await first.value
        let second = Task { await useCase.run() }
        await useCase.runs.waitForCount(2)
        second.cancel()
        await second.value

        #expect(useCase.runEvents.values == [.started(1), .ended(1), .started(2), .ended(2)])
    }

    @Test("a held run records its cancel and then stays in run() until the test releases it")
    func heldRunWaitsForTheRelease() async {
        let useCase = FakeEffectCatalogUseCase()
        useCase.holdCancelledRuns()
        let returned = Collector<Void>()
        let task = Task {
            await useCase.run()
            returned.append(())
        }
        await useCase.runs.waitForCount(1)

        task.cancel()
        await useCase.runCancellations.waitForCount(1)
        #expect(useCase.heldRunCount == 1, "the cancel arrived, and the run is held anyway")
        #expect(useCase.runEvents.values == [.started(1)])

        useCase.releaseCancelledRuns()
        await returned.waitForCount(1)
        #expect(useCase.heldRunCount == 0)
        #expect(useCase.runEvents.values == [.started(1), .ended(1)])
    }

    @Test("a release ends the holding: a run cancelled after it returns at once, and releasing with nothing held does nothing")
    func releaseEndsTheHolding() async {
        let useCase = FakeEffectCatalogUseCase()
        useCase.holdCancelledRuns()
        useCase.releaseCancelledRuns()
        useCase.releaseCancelledRuns()

        let task = Task { await useCase.run() }
        await useCase.runs.waitForCount(1)
        task.cancel()
        await task.value

        #expect(useCase.runEvents.values == [.started(1), .ended(1)])
        #expect(useCase.runCancellations.count == 1)
    }

    @Test("observe starts from the state published before it, then yields each publish")
    func observeStartsFromTheCurrentValue() async {
        let useCase = FakeEffectCatalogUseCase()
        let first = EffectCatalogState.fixture([chromatic])
        let second = EffectCatalogState.fixture([chromatic, glitch], outcome: .prepared)
        useCase.publish(first)

        let seen = Collector<EffectCatalogState>()
        let consumer = Task { for await state in useCase.observe() { seen.append(state) } }
        await seen.waitForCount(1)
        #expect(seen.values == [first], "the current value comes first, with nothing published since")

        useCase.publish(second)
        await seen.waitForCount(2)
        consumer.cancel()
        await consumer.value
        #expect(seen.values == [first, second])
    }

    @Test("a fake made without a state yields nothing until the first publish")
    func observeWithoutAState() async {
        let useCase = FakeEffectCatalogUseCase()
        let seen = Collector<EffectCatalogState>()
        let consumer = Task { for await state in useCase.observe() { seen.append(state) } }
        await useCase.observations.waitForCount(1)
        #expect(seen.count == 0)

        let state = EffectCatalogState.fixture([chromatic])
        useCase.publish(state)
        await seen.waitForCount(1)
        consumer.cancel()
        await consumer.value
        #expect(seen.values == [state])
    }

    @Test("a stream that ends is recorded, and a publish after it reaches nobody")
    func observationEnds() async {
        let useCase = FakeEffectCatalogUseCase(state: .fixture([chromatic]))
        let seen = Collector<EffectCatalogState>()
        let consumer = Task { for await state in useCase.observe() { seen.append(state) } }
        await seen.waitForCount(1)

        consumer.cancel()
        await useCase.observationTerminations.waitForCount(1)
        useCase.publish(.fixture([glitch]))
        await consumer.value
        #expect(seen.count == 1)
    }

    @Test("a run that is cancelled ends the open streams and leaves nothing current, as the live one does")
    func runEndsTheStreams() async {
        let useCase = FakeEffectCatalogUseCase(state: .fixture([chromatic]))
        let seen = Collector<EffectCatalogState>()
        let ended = Collector<Void>()
        let consumer = Task {
            for await state in useCase.observe() { seen.append(state) }
            ended.append(())
        }
        await seen.waitForCount(1)
        let run = Task { await useCase.run() }
        await useCase.runs.waitForCount(1)

        run.cancel()
        await ended.waitForCount(1)
        await consumer.value
        await useCase.observationTerminations.waitForCount(1)

        let later = Collector<EffectCatalogState>()
        let next = Task { for await state in useCase.observe() { later.append(state) } }
        await useCase.observations.waitForCount(2)
        useCase.publish(.fixture([glitch]))
        await later.waitForCount(1)
        next.cancel()
        await next.value
        #expect(seen.values == [.fixture([chromatic])])
        #expect(
            later.values == [.fixture([glitch])], "the state of the run that ended is not replayed: a stream opened after waits for the next publish")
    }

    @Test("select records the id and answers the scripted outcome, prepared unless told otherwise")
    func selectIsRecorded() async {
        let useCase = FakeEffectCatalogUseCase()
        #expect(await useCase.select(.package("glitch")) == .prepared)

        useCase.script(selectOutcome: .failed(.compileFailed))
        #expect(await useCase.select(.package("broken")) == .failed(.compileFailed))
        useCase.script(selectOutcome: .unavailable(.sourceMissing))
        #expect(await useCase.select(.package("gone")) == .unavailable(.sourceMissing))

        #expect(useCase.selections.values == [.package("glitch"), .package("broken"), .package("gone")])
    }

    @Test("openEffectsFolder is recorded")
    func openFolderIsRecorded() {
        let useCase = FakeEffectCatalogUseCase()
        useCase.openEffectsFolder()
        useCase.openEffectsFolder()
        #expect(useCase.folderOpens.count == 2)
    }
}
