import Domain
import TestDoubles
import TestSupport
import Testing

/// What next and previous effect decides: the neighbouring ready effect is chosen the way `select` chooses it, and
/// nothing moves when no other ready effect exists. Each sentence of the issue's Interface is one test. The runtime is
/// answered by the test (`EffectCatalogRig.answer`), so each interleaving is written down and nothing waits on time.
@Suite("EffectCatalogUseCase adjacent", .timeLimit(.minutes(1)))
struct EffectCatalogAdjacentTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    @Test("with the first effect chosen, next prepares the second, answers prepared, moves the choice and writes it down")
    func nextFromTheFirstPreparesTheSecond() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let adjacent = Task { await rig.subject.selectAdjacent(.next) }
        let request = await rig.answer(2)
        let outcome = await adjacent.value
        await watcher.states.waitForCount(2)

        #expect(request.effect == Rig.glitchSource)
        #expect(outcome == .prepared)
        #expect(watcher.states.values.last == Rig.state(selection: glitch, outcome: .prepared))
        #expect(rig.settings.writes.values == [glitch.id])
        await rig.stop(run)
    }

    @Test("with the first effect chosen, previous wraps round to the last one and prepares it")
    func previousFromTheFirstWrapsRound() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let adjacent = Task { await rig.subject.selectAdjacent(.previous) }
        let request = await rig.answer(2)
        let outcome = await adjacent.value
        await watcher.states.waitForCount(2)

        #expect(request.effect == Rig.otherSource)
        #expect(outcome == .prepared)
        #expect(watcher.states.values.last == Rig.state(selection: other, outcome: .prepared))
        #expect(rig.settings.writes.values == [other.id])
        await rig.stop(run)
    }

    @Test(
        "with one ready effect and no other, next and previous have no neighbour: nil, and nothing is prepared or written",
        arguments: EffectStep.allCases)
    func loneReadyEffectHasNoNeighbour(_ step: EffectStep) async {
        let broken = EffectCatalogEntry.fixture(.package("broken"), availability: .broken(.sourceMissing))
        let rig = Rig(entries: [bundled, broken])
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(await rig.subject.selectAdjacent(step) == nil)

        #expect(rig.runtime.prepareRequests.count == 1, "nothing was prepared for a neighbour")
        #expect(rig.settings.writes.values.isEmpty, "nothing was chosen")
        #expect(watcher.states.values == [Rig.state([bundled, broken], selection: bundled, outcome: .prepared)])
        await rig.stop(run)
    }

    @Test("when the neighbour's prepare fails, the outcome is the one select gives, and the choice still moves to it")
    func failedNeighbourIsTheOutcome() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let adjacent = Task { await rig.subject.selectAdjacent(.next) }
        await rig.answer(2, with: .failure(.compileFailed))
        let outcome = await adjacent.value
        await watcher.states.waitForCount(2)

        #expect(outcome == .failed(.compileFailed))
        #expect(watcher.states.values.last == Rig.state(selection: glitch, outcome: .failed(.compileFailed)))
        #expect(rig.settings.writes.values == [glitch.id])
        await rig.stop(run)
    }

    @Test("the fake records each step and answers the outcome scripted for it, prepared unless told otherwise")
    func fakeRecordsStepsAndAnswersScripted() async {
        let fake = FakeEffectCatalogUseCase()
        #expect(await fake.selectAdjacent(.next) == .prepared)
        fake.script(adjacentOutcome: nil)
        #expect(await fake.selectAdjacent(.previous) == nil)
        #expect(fake.adjacentSteps.values == [.next, .previous])
    }
}
