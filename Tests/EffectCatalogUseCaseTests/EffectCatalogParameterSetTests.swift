import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// What setting a parameter of the chosen effect does (`docs/hackathon/mvp-cd/specs/parameters.md`): the value is clamped
/// and snapped by its declaration, the state shows the result, the runtime is handed the new block, and nothing is prepared.
/// Each rule is one test, named as the spec sentence it checks. Every `prepare` is answered by the test, and nothing waits
/// on time.
@Suite("EffectCatalogUseCase parameter set", .timeLimit(.minutes(1)))
struct EffectCatalogParameterSetTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    /// The package `glitch` reads: an effect that declares the six example parameters.
    private static let declaring = EffectSource(name: "Glitch", source: "glitch v1", parameters: EffectParameterSpec.all)

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

    /// The first four bytes of a block, which hold the first field the shader reads.
    private static func leadingWord(_ block: EffectParameterBlock) -> [UInt8] {
        Array(block.bytes.prefix(4))
    }

    // MARK: - Clamping and rejecting

    @Test("a value beyond the range is clamped to it: the state shows the clamped value, and the runtime gets its block")
    func setClampsToTheRange() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        await rig.subject.setParameter("strength", to: .float(7))
        await watcher.states.waitForCount(2)

        #expect(Self.value(of: "strength", in: watcher.states.values.last) == .float(1))
        #expect(rig.runtime.parameterWrites.count == 1)
        #expect(Self.leadingWord(rig.runtime.parameterWrites.values[0].block) == [0x00, 0x00, 0x80, 0x3F], "7 is clamped to 1.0")
        #expect(rig.runtime.parameterWrites.values[0].source == Self.declaring)
        await rig.stop(run)
    }

    @Test("a set that changes nothing writes and publishes nothing, including a clamp to the value the parameter already holds")
    func setThatChangesNothingIsNotWritten() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        await rig.subject.setParameter("strength", to: .float(0.5))  // the default already
        await rig.subject.setParameter("strength", to: .float(7))  // clamped to 1: a change, written once
        await rig.subject.setParameter("strength", to: .float(9))  // clamped to 1 again: the value held now
        #expect(rig.runtime.parameterWrites.count == 1)

        await rig.subject.setParameter("rings", to: .int(9))  // a change, so the states can be counted after it
        await watcher.states.waitForCount(3)

        #expect(rig.runtime.parameterWrites.count == 2)
        #expect(watcher.states.count == 3, "the initial state, the clamp to 1 and the rings change are the only states")
        await rig.stop(run)
    }

    @Test("an id the chosen effect does not declare, or a value of another kind, is rejected: nothing is written or published, and it is logged")
    func unknownOrMismatchedSetIsRejected() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        await rig.subject.setParameter("nope", to: .float(0.5))
        await rig.subject.setParameter("rings", to: .bool(true))
        #expect(rig.runtime.parameterWrites.count == 0)
        #expect(
            rig.log.messages(in: .effect) == [
                "effect 'Glitch' selected",
                "parameter 'nope' of 'Glitch' rejected",
                "parameter 'rings' of 'Glitch' rejected",
            ])

        await rig.subject.setParameter("rings", to: .int(9))  // a change, so the states can be checked after the rejections
        await watcher.states.waitForCount(2)
        #expect(watcher.states.count == 2, "the rejected sets published no state")
        #expect(Self.value(of: "rings", in: watcher.states.values.last) == .int(9))
        #expect(rig.runtime.prepareRequests.count == 1, "a set never prepares")
        await rig.stop(run)
    }

    @Test("a set on an effect that declares no parameters is rejected, and its state lists none")
    func setOnAnUndeclaredEffectIsRejected() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        await rig.subject.setParameter("strength", to: .float(0.5))

        #expect(rig.runtime.parameterWrites.count == 0)
        #expect(rig.log.messages(in: .effect).last == "parameter 'strength' of 'Chromatic Grain' rejected")
        #expect(watcher.states.values.last?.parameters.isEmpty == true)
        await rig.stop(run)
    }

    @Test("a set or a reset before any effect is chosen is ignored with a log, and does not fail")
    func callsBeforeAChoiceAreIgnored() async {
        let rig = Rig()

        await rig.subject.setParameter("strength", to: .float(0.25))
        await rig.subject.resetParameters()

        #expect(
            rig.log.messages(in: .effect) == [
                "parameter 'strength' ignored: no effect is chosen",
                "parameter reset ignored: no effect is chosen",
            ])
        #expect(rig.runtime.parameterWrites.count == 0)
        #expect(rig.runtime.prepareRequests.count == 0)
    }

    @Test("a set made while another effect is being chosen is ignored, so the values of the effect it replaces never reach the new one")
    func setWhileTheChoiceIsMadeIsIgnored() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let run = rig.start()
        await rig.answer(1)

        rig.settings.holdWrites()
        let choice = Task { await rig.subject.select(other.id) }
        await rig.settings.heldRequests.waitForCount(1)  // other is chosen, and is still being remembered

        await rig.subject.setParameter("rings", to: .int(9))
        #expect(rig.runtime.parameterWrites.count == 0)
        #expect(rig.log.messages(in: .effect).last == "parameter 'rings' ignored: no effect is chosen")

        rig.settings.holdWrites(false)
        rig.settings.complete(rig.settings.heldRequests.values[0])
        await rig.answer(2)
        #expect(await choice.value == .prepared)
        #expect(rig.runtime.parameterWrites.count == 0)
        await rig.stop(run)
    }

    // MARK: - Writing to the runtime

    @Test("sets reach the runtime in the order they were made, and none of them prepares the effect")
    func setsReachTheRuntimeInOrder() async throws {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let run = rig.start()
        await rig.answer(1)

        await rig.subject.setParameter("rings", to: .int(9))
        await rig.subject.setParameter("strength", to: .float(0.25))
        await rig.subject.setParameter("rings", to: .int(2))

        let first = try #require(Self.defaults.setting("rings", to: .int(9)))
        let second = try #require(first.setting("strength", to: .float(0.25)))
        let third = try #require(second.setting("rings", to: .int(2)))
        #expect(rig.runtime.parameterWrites.values.map(\.block) == [first.block, second.block, third.block])
        #expect(rig.runtime.parameterWrites.values.allSatisfy { $0.source == Self.declaring })
        #expect(rig.runtime.prepareRequests.count == 1, "a write never calls prepare")
        await rig.stop(run)
    }

    // MARK: - Reset

    @Test("a reset puts every parameter back to its default, and a reset when they already are the defaults writes nothing")
    func resetRestoresTheDefaults() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        await rig.subject.setParameter("rings", to: .int(9))
        await watcher.states.waitForCount(2)
        await rig.subject.resetParameters()
        await watcher.states.waitForCount(3)

        #expect(watcher.states.values.last?.parameters == Self.defaults.states)
        #expect(rig.runtime.parameterWrites.count == 2)
        #expect(rig.runtime.parameterWrites.values.last?.block == Self.defaults.block)

        await rig.subject.resetParameters()
        #expect(rig.runtime.parameterWrites.count == 2, "already at the defaults: nothing is written")
        await rig.stop(run)
    }

    // MARK: - A reload keeps the values

    @Test("a hot reload keeps the values set before it, clamped to a range the edited declaration narrowed")
    func hotReloadKeepsTheValues() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        await rig.subject.setParameter("strength", to: .float(0.75))
        await watcher.states.waitForCount(2)

        let narrowed = EffectParameterSpec(
            id: "strength", label: "Strength", kind: .float(min: 0, max: 0.5, step: 0.25, defaultValue: 0.5))
        let edited = EffectSource(
            name: "Glitch", source: "glitch v2", parameters: EffectParameterSpec.all.map { $0.id == "strength" ? narrowed : $0 })
        rig.packages.script(.success(edited), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        let reload = await rig.answer(2)
        await watcher.states.waitForCount(3)

        #expect(Self.value(of: "strength", in: watcher.states.values.last) == .float(0.5))
        #expect(Self.leadingWord(reload.parameters) == [0x00, 0x00, 0x00, 0x3F], "the reloaded block starts with 0.5")
        await rig.stop(run)
    }

    @Test("a reload drops a parameter the edited declaration no longer has, and a value whose type changed starts from its default")
    func reloadFollowsTheDeclaration() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        await rig.subject.setParameter("strength", to: .float(0.75))
        await rig.subject.setParameter("rings", to: .int(9))
        await watcher.states.waitForCount(3)

        let retyped = EffectParameterSpec(id: "rings", label: "Rings", kind: .float(min: 1, max: 16, step: nil, defaultValue: 4))
        let edited = EffectSource(
            name: "Glitch", source: "glitch v2",
            parameters: EffectParameterSpec.all.filter { $0.id != "mode" }.map { $0.id == "rings" ? retyped : $0 })
        rig.packages.script(.success(edited), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.answer(2)
        await watcher.states.waitForCount(4)

        let last = watcher.states.values.last
        #expect(last?.parameters.map(\.spec.id) == ["strength", "rings", "inverted", "tint", "center"], "the dropped parameter leaves the list")
        #expect(Self.value(of: "strength", in: last) == .float(0.75), "a value the new declaration still allows is kept")
        #expect(Self.value(of: "rings", in: last) == .float(4), "a value whose type changed starts from the new default")
        await rig.stop(run)
    }
}
