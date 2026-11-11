import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// What a choice starts from when the settings hold values for its effect (`docs/hackathon/mvp-cd/specs/parameters.md`):
/// the stored values are read once, when an effect that declares parameters is chosen or first listed, and the runtime is
/// prepared with them. A hot reload or a re-choice of the effect already prepared reads nothing, because the values in
/// memory are the newest. Each rule is one test, named as the spec sentence it checks. Every `prepare` is answered by the
/// test, and the stored-values read is held where a test overtakes it. Nothing waits on time.
@Suite("EffectCatalogUseCase parameter restore", .timeLimit(.minutes(1)))
struct EffectCatalogParameterRestoreTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    /// The package `glitch` reads: an effect that declares the six example parameters.
    private static let declaring = EffectSource(name: "Glitch", source: "glitch v1", parameters: EffectParameterSpec.all)

    /// The package `other` reads: an effect that declares one parameter.
    private static let otherDeclaring = EffectSource(name: "Other", source: "other v1", parameters: [EffectParameterSpec.strength])

    /// The sources of a rig in which `glitch` reads `declared` and the others read their usual sources.
    private static func glitchReads(_ declared: EffectSource) -> [EffectID: EffectSource] {
        [Rig.bundled.id: Rig.bundledSource, Rig.glitch.id: declared, Rig.other.id: Rig.otherSource]
    }

    /// The model with every declared parameter at its default.
    private static var defaults: ParameterModel { ParameterModel(specs: EffectParameterSpec.all, restoring: [:]) }

    /// The value the state shows for the parameter `id`, or nil when the state lists no such parameter.
    private static func value(of id: String, in state: EffectCatalogState?) -> EffectParameterValue? {
        state?.parameters.first(where: { $0.spec.id == id })?.value
    }

    // MARK: - The first block of a chosen effect

    @Test("a chosen effect's saved values are the block its first prepare carries, and its state lists them")
    func savedValuesArePrepared() async {
        let saved: [String: EffectParameterValue] = ["rings": .int(9), "inverted": .bool(true)]
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring), parameters: [glitch.id: saved])
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        let restored = ParameterModel(specs: EffectParameterSpec.all, restoring: saved)
        #expect(request.parameters == restored.block)
        #expect(watcher.states.values.map(\.parameters) == [restored.states])
        #expect(Self.value(of: "rings", in: watcher.states.values.last) == .int(9))
        #expect(rig.settings.parameterReads.values == [glitch.id], "the stored values are read once, for the first choice")
        #expect(rig.settings.parameterWrites.count == 0, "restoring is not choosing: nothing is written back")
        await rig.stop(run)
    }

    @Test(
        "a stored value beyond its range is clamped, an id no spec declares is dropped, and a value of another type or a missing one takes its default"
    )
    func storedValuesAreReconciled() async {
        let saved: [String: EffectParameterValue] = [
            "rings": .int(99),  // beyond 1...16: clamped to 16
            "gone": .bool(true),  // no spec declares it: dropped
            "inverted": .int(1),  // another kind than the spec's: its default
            // "strength" is not stored: its default
        ]
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring), parameters: [glitch.id: saved])
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        let state = watcher.states.values.last
        #expect(request.parameters == ParameterModel(specs: EffectParameterSpec.all, restoring: saved).block)
        #expect(Self.value(of: "rings", in: state) == .int(16))
        #expect(Self.value(of: "inverted", in: state) == .bool(false))
        #expect(Self.value(of: "strength", in: state) == .float(0.5))
        #expect(state?.parameters.map(\.spec.id) == EffectParameterSpec.all.map(\.id), "the dropped id is not listed")
        await rig.stop(run)
    }

    @Test("an effect whose settings hold no values starts from every default, and the read still happened")
    func nothingStoredStartsFromDefaults() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(request.parameters == Self.defaults.block)
        #expect(watcher.states.values.map(\.parameters) == [Self.defaults.states])
        #expect(rig.settings.parameterReads.values == [glitch.id])
        await rig.stop(run)
    }

    @Test("a chosen effect that declares no parameters reads none of the stored values")
    func undeclaredEffectReadsNothing() async {
        let rig = Rig(parameters: [bundled.id: ["rings": .int(9)]])
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(request.parameters == .none)
        #expect(watcher.states.values.map(\.parameters) == [[]])
        #expect(rig.settings.parameterReads.values.isEmpty, "there is nothing to restore for an effect without declarations")
        await rig.stop(run)
    }

    // MARK: - Memory is the newest

    @Test("a hot reload keeps the values in memory and reads the settings no more")
    func hotReloadReadsNothing() async {
        let rig = Rig(
            persisted: glitch.id, sources: Self.glitchReads(Self.declaring), parameters: [glitch.id: ["rings": .int(2)]])
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        await rig.subject.setParameter("rings", to: .int(9))  // newer than the stored 2
        await watcher.states.waitForCount(2)
        let renamed = EffectParameterSpec(id: "rings", label: "Count", kind: EffectParameterSpec.rings.kind)
        let relabelled = EffectParameterSpec.all.map { $0.id == "rings" ? renamed : $0 }
        // A label change is a change of the state, so the reload publishes and the watcher can wait for it.
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2", parameters: relabelled)), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        let reload = await rig.answer(2)
        await watcher.states.waitForCount(3)

        #expect(rig.settings.parameterReads.values == [glitch.id], "one read, for the first choice")
        #expect(reload.parameters == ParameterModel(specs: relabelled, restoring: ["rings": .int(9)]).block)
        #expect(Self.value(of: "rings", in: watcher.states.values.last) == .int(9))
        await rig.stop(run)
    }

    @Test("choosing the effect that is already prepared again reads the settings no more and keeps the values in memory")
    func rechoosingThePreparedEffectReadsNothing() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring), parameters: [glitch.id: ["rings": .int(2)]])
        let run = rig.start()
        await rig.answer(1)

        await rig.subject.setParameter("rings", to: .int(9))
        let again = Task { await rig.subject.select(glitch.id) }
        let request = await rig.answer(2)
        #expect(await again.value == .prepared)

        #expect(rig.settings.parameterReads.values == [glitch.id], "the choice of the prepared effect read nothing")
        #expect(request.parameters == ParameterModel(specs: EffectParameterSpec.all, restoring: ["rings": .int(9)]).block)
        await rig.stop(run)
    }

    // MARK: - Each effect its own

    @Test("choosing an effect again after another reads its stored values again, each effect its own")
    func rechoiceReadsTheSettingsAgain() async {
        let savedGlitch: [String: EffectParameterValue] = ["rings": .int(9)]
        let savedOther: [String: EffectParameterValue] = ["strength": .float(0.25)]
        let sources: [EffectID: EffectSource] = [bundled.id: Rig.bundledSource, glitch.id: Self.declaring, other.id: Self.otherDeclaring]
        let rig = Rig(persisted: glitch.id, sources: sources, parameters: [glitch.id: savedGlitch, other.id: savedOther])
        let run = rig.start()
        await rig.answer(1)

        let toOther = Task { await rig.subject.select(other.id) }
        await rig.answer(2)
        #expect(await toOther.value == .prepared)

        let back = Task { await rig.subject.select(glitch.id) }
        let request = await rig.answer(3)
        #expect(await back.value == .prepared)

        #expect(rig.settings.parameterReads.values == [glitch.id, other.id, glitch.id])
        #expect(
            rig.runtime.prepareRequests.values[1].parameters == ParameterModel(specs: [EffectParameterSpec.strength], restoring: savedOther).block)
        #expect(request.parameters == ParameterModel(specs: EffectParameterSpec.all, restoring: savedGlitch).block)
        await rig.stop(run)
    }

    // MARK: - A read that is overtaken

    @Test("a read of stored values that a newer choice overtakes prepares nothing: the newer choice owns the effect")
    func choiceOvertakesARestoreRead() async {
        let rig = Rig(sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)  // the bundled effect, which declares nothing
        await watcher.states.waitForCount(1)

        rig.settings.holdParameterReads()
        let older = Task { await rig.subject.select(glitch.id) }
        await rig.settings.heldParameterReads.waitForCount(1)  // glitch's stored values are being read...
        let newer = Task { await rig.subject.select(other.id) }  // ...when other, which declares nothing, is chosen
        await rig.answer(2)
        #expect(await newer.value == .prepared)
        await watcher.states.waitForCount(2)

        #expect(rig.settings.releaseParameterRead(rig.settings.heldParameterReads.values[0]))
        #expect(await older.value == .unavailable(nil), "the older choice prepared nothing, and says so")

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.bundledSource, Rig.otherSource], "glitch was never prepared")
        #expect(watcher.states.values.map(\.selection) == [bundled.id, other.id])
        #expect(watcher.states.values.last?.parameters.isEmpty == true, "the state lists the parameters of other, which has none")
        await rig.stop(run)
    }

    @Test("a listing reading the stored values of its chosen effect, when a newer choice takes over, prepares nothing for that effect")
    func choiceOvertakesAListingsRestoreRead() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        rig.settings.holdParameterReads()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.settings.heldParameterReads.waitForCount(1)  // the listing is reading glitch's stored values...

        let newer = Task { await rig.subject.select(other.id) }  // ...when other, which declares nothing, is chosen
        await rig.answer(1)
        #expect(await newer.value == .prepared)
        await watcher.states.waitForCount(1)

        #expect(rig.settings.releaseParameterRead(rig.settings.heldParameterReads.values[0]))
        // The run takes one listing at a time: a listing published now is dealt with once the held one has ended.
        rig.packages.publish([bundled, glitch, other, EffectCatalogEntry.fixture(.package("later"))])
        await watcher.states.waitForCount(2)

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.otherSource], "glitch was never prepared")
        #expect(rig.settings.parameterReads.values == [glitch.id])
        #expect(watcher.states.values.map(\.selection) == [other.id, other.id])
        #expect(watcher.states.values.last?.outcome == .prepared)
        await rig.stop(run)
    }
}
