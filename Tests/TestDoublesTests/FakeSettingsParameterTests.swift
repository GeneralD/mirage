import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeSettingsRepository parameters", .timeLimit(.minutes(1)))
struct FakeSettingsParameterTests {
    private let glitch: EffectID = .package("glitch")
    private let chromatic: EffectID = .bundled("Chromatic Grain")

    @Test("parameterValues answers the parameters it was made with, for the effect they belong to")
    func initialParameters() async {
        let settings = FakeSettingsRepository(parameters: [glitch: ["strength": .float(0.5)]])
        #expect(await settings.parameterValues(of: glitch) == ["strength": .float(0.5)])
        #expect(settings.parameterWrites.count == 0, "what it started with is not a write")
    }

    @Test("an effect with no stored parameters answers an empty dictionary")
    func unknownEffect() async {
        #expect(await FakeSettingsRepository().parameterValues(of: glitch) == [:])
    }

    @Test("parameter reads are recorded in call order, with the effect each one asked for")
    func readsAreRecordedInOrder() async {
        let settings = FakeSettingsRepository()
        _ = await settings.parameterValues(of: glitch)
        _ = await settings.parameterValues(of: chromatic)
        _ = await settings.parameterValues(of: glitch)
        #expect(settings.parameterReads.values == [glitch, chromatic, glitch])
    }

    @Test("a write is stored and recorded in call order, and the next read answers what it stored")
    func writesAreStoredAndRecorded() async {
        let settings = FakeSettingsRepository()
        await settings.setParameterValues(["strength": .float(0.5)], of: glitch)
        #expect(await settings.parameterValues(of: glitch) == ["strength": .float(0.5)])
        await settings.setParameterValues(["rings": .int(9)], of: glitch)
        #expect(await settings.parameterValues(of: glitch) == ["rings": .int(9)])
        #expect(
            settings.parameterWrites.values == [
                FakeSettingsRepository.ParameterWrite(id: glitch, values: ["strength": .float(0.5)]),
                FakeSettingsRepository.ParameterWrite(id: glitch, values: ["rings": .int(9)]),
            ])
    }

    @Test("a write replaces the values of its own effect and leaves the other effects alone")
    func writeTouchesOnlyItsEffect() async {
        let settings = FakeSettingsRepository(parameters: [chromatic: ["mode": .choice(1)]])
        await settings.setParameterValues(["strength": .float(0.5)], of: glitch)
        await settings.setParameterValues(["rings": .int(9)], of: glitch)
        #expect(await settings.parameterValues(of: glitch) == ["rings": .int(9)], "a write replaces, it does not merge")
        #expect(await settings.parameterValues(of: chromatic) == ["mode": .choice(1)], "the other effect is left alone")
    }

    @Test("a held parameter read is recorded, parks, and returns once it is released")
    func heldRead() async {
        let settings = FakeSettingsRepository(parameters: [glitch: ["strength": .float(0.5)]])
        settings.holdParameterReads()
        let read = Task { await settings.parameterValues(of: glitch) }
        await settings.heldParameterReads.waitForCount(1)
        let request = settings.heldParameterReads.values[0]
        #expect(request.effect == glitch)
        #expect(settings.parameterReads.values == [glitch], "the call is recorded before it parks")
        #expect(settings.pendingCount == 0, "a parked parameter read is not a pending call")
        #expect(settings.heldRequests.count == 0, "nor is it a held selection or disabled request")

        #expect(settings.releaseParameterRead(request))
        #expect(await read.value == ["strength": .float(0.5)])
    }

    @Test("a parked read answers the values stored when it began, and a write made while it is parked is not seen by it")
    func heldReadAnswersItsStart() async {
        let settings = FakeSettingsRepository(parameters: [glitch: ["strength": .float(0.5)]])
        settings.holdParameterReads()
        let read = Task { await settings.parameterValues(of: glitch) }
        await settings.heldParameterReads.waitForCount(1)
        let request = settings.heldParameterReads.values[0]

        settings.holdParameterReads(false)
        await settings.setParameterValues(["strength": .float(0.25)], of: glitch)  // answered at once: lands while the read is parked
        #expect(await settings.parameterValues(of: glitch) == ["strength": .float(0.25)], "a read after the write sees it")
        #expect(settings.releaseParameterRead(request))
        #expect(await read.value == ["strength": .float(0.5)], "the parked read began before the write")
    }

    @Test("holdParameterReads(false) answers at once again, and a read already parked stays parked")
    func releasedHold() async {
        let settings = FakeSettingsRepository(parameters: [glitch: ["strength": .float(0.5)]])
        settings.holdParameterReads()
        let parked = Task { await settings.parameterValues(of: glitch) }
        await settings.heldParameterReads.waitForCount(1)
        let request = settings.heldParameterReads.values[0]
        settings.holdParameterReads(false)

        #expect(await settings.parameterValues(of: glitch) == ["strength": .float(0.5)], "answers at once now")
        #expect(settings.heldParameterReads.count == 1, "the read after the release is not held")
        #expect(settings.releaseParameterRead(request), "the earlier read is still parked, so its release finds it")
        #expect(await parked.value == ["strength": .float(0.5)])
    }

    @Test("a parked read is released once, and a request from another repository releases nothing")
    func releaseOnce() async {
        let settings = FakeSettingsRepository()
        let stranger = FakeSettingsRepository()
        settings.holdParameterReads()
        stranger.holdParameterReads()
        let read = Task { await settings.parameterValues(of: glitch) }
        let strangerRead = Task { await stranger.parameterValues(of: glitch) }
        await settings.heldParameterReads.waitForCount(1)
        await stranger.heldParameterReads.waitForCount(1)
        let request = settings.heldParameterReads.values[0]
        let strangerRequest = stranger.heldParameterReads.values[0]
        #expect(request.id == strangerRequest.id, "both instances numbered their first parked read 1")

        #expect(!stranger.releaseParameterRead(request), "the id alone is not an identity")
        #expect(!settings.releaseParameterRead(strangerRequest), "the other instance's request releases nothing here")
        #expect(settings.releaseParameterRead(request))
        #expect(!settings.releaseParameterRead(request), "it was already released")

        #expect(stranger.releaseParameterRead(strangerRequest), "the stranger's own read is still parked")
        _ = await read.value
        _ = await strangerRead.value
    }

    @Test("holdReads and holdWrites do not park a parameter call")
    func selectionHoldsDoNotParkParameters() async {
        let settings = FakeSettingsRepository()
        settings.holdReads()
        settings.holdWrites()
        await settings.setParameterValues(["strength": .float(0.5)], of: glitch)
        #expect(await settings.parameterValues(of: glitch) == ["strength": .float(0.5)], "answers at once")
        #expect(settings.heldRequests.count == 0)
        #expect(settings.heldParameterReads.count == 0)
        settings.holdReads(false)
        settings.holdWrites(false)
    }

    @Test("parameter calls do not move reads, writes, heldRequests or pendingCount")
    func parameterCallsLeaveSelectionCountsAlone() async {
        let settings = FakeSettingsRepository()
        settings.holdParameterReads()
        let read = Task { await settings.parameterValues(of: glitch) }
        await settings.heldParameterReads.waitForCount(1)
        await settings.setParameterValues(["rings": .int(9)], of: glitch)

        #expect(settings.reads.count == 0)
        #expect(settings.writes.count == 0)
        #expect(settings.heldRequests.count == 0)
        #expect(settings.pendingCount == 0)
        #expect(settings.releaseParameterRead(settings.heldParameterReads.values[0]))
        _ = await read.value
    }
}
