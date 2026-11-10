import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeSettingsRepository disabled effects", .timeLimit(.minutes(1)))
struct FakeSettingsDisabledTests {
    private let glitch = DisabledEffectRecord(
        id: .package("glitch"), fingerprint: EffectFingerprint(value: "f1"), reason: .failure(.timeout), retriesAutomatically: false)
    private let ripple = DisabledEffectRecord(
        id: .package("ripple"), fingerprint: EffectFingerprint(value: "f2"), reason: .overBudget, retriesAutomatically: true)

    @Test("disabledEffects answers the records it was made with, and each read is recorded")
    func initialRecords() async {
        let settings = FakeSettingsRepository(disabled: [glitch])
        #expect(await settings.disabledEffects() == [glitch])
        #expect(settings.disabledReads.count == 1)
        #expect(settings.disabledWrites.count == 0, "what it started with is not a write")
        #expect(settings.reads.count == 0, "reading the records is not reading the selection")
    }

    @Test("nothing recorded is an empty list")
    func nothingRecorded() async {
        #expect(await FakeSettingsRepository().disabledEffects() == [])
    }

    @Test("setDisabledEffects replaces what disabledEffects answers, and each array is recorded in call order")
    func writesReplace() async {
        let settings = FakeSettingsRepository(disabled: [glitch])
        await settings.setDisabledEffects([ripple])
        #expect(await settings.disabledEffects() == [ripple])
        await settings.setDisabledEffects([])
        #expect(await settings.disabledEffects() == [])
        #expect(settings.disabledWrites.values == [[ripple], []])
        #expect(settings.writes.count == 0, "the records do not touch the selection")
    }

    @Test("a held disabled write stores and records its array, then stays parked until it is completed")
    func heldDisabledWrite() async {
        let settings = FakeSettingsRepository()
        settings.holdDisabledWrites()
        let returned = Collector<Void>()
        let write = Task {
            await settings.setDisabledEffects([glitch])
            returned.append(())
        }
        await settings.heldRequests.waitForCount(1)
        let request = settings.heldRequests.values[0]
        #expect(request.call == .writeDisabled([glitch]))
        #expect(settings.disabledWrites.values == [[glitch]])
        #expect(await settings.disabledEffects() == [glitch], "remembered already, though the call has not returned yet")
        #expect(returned.count == 0)

        #expect(settings.complete(request))
        await write.value
        #expect(returned.count == 1)
    }

    @Test("holdDisabledWrites(false) answers at once again, and a write that is already parked stays parked")
    func releasedHold() async {
        let settings = FakeSettingsRepository()
        settings.holdDisabledWrites()
        let parked = Task { await settings.setDisabledEffects([glitch]) }
        await settings.heldRequests.waitForCount(1)
        settings.holdDisabledWrites(false)

        await settings.setDisabledEffects([ripple])  // not held: returns while the first write is parked
        #expect(settings.pendingCount == 1)
        #expect(settings.complete(settings.heldRequests.values[0]))
        await parked.value
    }

    @Test("holdWrites does not park a disabled write, and holdDisabledWrites does not park a selection")
    func holdsAreSeparate() async {
        let settings = FakeSettingsRepository()
        settings.holdWrites()
        await settings.setDisabledEffects([glitch])
        #expect(settings.heldRequests.count == 0, "a disabled write is not a selection write")
        settings.holdWrites(false)

        settings.holdDisabledWrites()
        await settings.setSelectedEffect(.package("glitch"))
        #expect(settings.heldRequests.count == 0, "a selection write is not a disabled write")
        settings.holdDisabledWrites(false)
        #expect(settings.pendingCount == 0)
    }

    @Test("a disabled write parked by another repository cannot be completed here")
    func strangerCompletesNothing() async {
        let settings = FakeSettingsRepository()
        let stranger = FakeSettingsRepository()
        settings.holdDisabledWrites()
        let write = Task { await settings.setDisabledEffects([glitch]) }
        await settings.heldRequests.waitForCount(1)
        let request = settings.heldRequests.values[0]

        #expect(!stranger.complete(request), "ids restart at 1 per instance, so the id alone is not an identity")
        #expect(settings.pendingCount == 1)
        #expect(settings.complete(request))
        #expect(!settings.complete(request), "it was already resumed")
        await write.value
    }
}
