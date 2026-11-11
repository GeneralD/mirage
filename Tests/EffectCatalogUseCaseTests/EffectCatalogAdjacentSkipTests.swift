import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// Effects that health switched off are skipped the way broken ones are: by the neighbour rule (`effectNeighbor`), and by the
/// session that chooses the neighbour (`selectAdjacent`). Each sentence of the issue's Interface is one test named after it.
@Suite("EffectCatalogUseCase adjacent skips disabled effects", .timeLimit(.minutes(1)))
struct EffectCatalogAdjacentSkipTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    private let a = EffectID.package("a")
    private let b = EffectID.package("b")
    private let c = EffectID.package("c")

    private func ready(_ id: EffectID) -> EffectCatalogEntry { .fixture(id) }

    @Test("with a, b and c all ready and b skipped, next from a is c and previous from c is a")
    func skippedMiddleIsJumpedOver() {
        let entries = [ready(a), ready(b), ready(c)]
        #expect(effectNeighbor(of: a, in: entries, step: .next, skipping: [b]) == c)
        #expect(effectNeighbor(of: c, in: entries, step: .previous, skipping: [b]) == a)
    }

    @Test("with the chosen b skipped, next is the first candidate a and previous is the last candidate c")
    func skippedChoiceStartsFromTheEnds() {
        let entries = [ready(a), ready(b), ready(c)]
        #expect(effectNeighbor(of: b, in: entries, step: .next, skipping: [b]) == a)
        #expect(effectNeighbor(of: b, in: entries, step: .previous, skipping: [b]) == c)
    }

    @Test("with a and b ready and b skipped, a has no neighbour in either direction")
    func loneCandidateHasNoNeighbour() {
        let entries = [ready(a), ready(b)]
        #expect(effectNeighbor(of: a, in: entries, step: .next, skipping: [b]) == nil)
        #expect(effectNeighbor(of: a, in: entries, step: .previous, skipping: [b]) == nil)
    }

    @Test("a call that passes no skipping answers as it did before: with a, b and c ready, next from a is b")
    func callWithoutSkippingIsUnchanged() {
        let entries = [ready(a), ready(b), ready(c)]
        #expect(effectNeighbor(of: a, in: entries, step: .next) == b)
        #expect(effectNeighbor(of: a, in: entries, step: .next, skipping: []) == b)
    }

    @Test("with glitch switched off, previous from other skips it and chooses the bundled effect, which is prepared and written down")
    func adjacentSkipsASwitchedOffEffect() async {
        let rig = Rig(persisted: glitch.id)
        let (run, watcher) = await rig.begin()
        rig.emit(.failure(.accessRevoked), of: Rig.glitchSource)
        await rig.answer(2)  // the fallback: the bundled effect stands in for the switched-off one
        _ = await rig.firstDisabled(in: watcher)  // the switched-off state is published once that has answered
        let choice = Task { await rig.subject.select(other.id) }
        await rig.answer(3)
        #expect(await choice.value == .prepared)

        let adjacent = Task { await rig.subject.selectAdjacent(.previous) }
        let request = await rig.answer(4)
        #expect(await adjacent.value == .prepared)

        #expect(request.effect == Rig.bundledSource, "the switched-off glitch was passed over, not chosen")
        #expect(rig.runtime.prepareRequests.count == 4)
        #expect(rig.settings.writes.values.last == bundled.id)
        await rig.stop(run)
    }
}
