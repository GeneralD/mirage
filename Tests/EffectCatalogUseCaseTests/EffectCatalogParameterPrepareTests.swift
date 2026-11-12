import Domain
import TestDoubles
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// What the session hands the runtime for a chosen effect's parameters, and what the panel lists for it
/// (`docs/hackathon/mvp-cd/specs/parameters.md`). Each rule of that preparation is one test, named as the spec sentence
/// it checks. Every `prepare` is answered by the test, so each order of answers is written down.
@Suite("EffectCatalogUseCase parameter prepare", .timeLimit(.minutes(1)))
struct EffectCatalogParameterPrepareTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    /// The package `glitch` reads: an effect that declares the six example parameters.
    private static let declaring = EffectSource(name: "Glitch", source: "glitch v1", parameters: EffectParameterSpec.all)

    /// The sources of a rig in which the bundled effect and `glitch` read the same `shared` source, and `other` reads its usual one.
    private static func sharing(_ shared: EffectSource) -> [EffectID: EffectSource] {
        [Rig.bundled.id: shared, Rig.glitch.id: shared, Rig.other.id: Rig.otherSource]
    }

    /// The sources of a rig in which `glitch` reads `declared` and the others read their usual sources.
    private static func glitchReads(_ declared: EffectSource) -> [EffectID: EffectSource] {
        [Rig.bundled.id: Rig.bundledSource, Rig.glitch.id: declared, Rig.other.id: Rig.otherSource]
    }

    /// Returns once the session has taken up every message sent before it: a choice of an unknown effect touches nothing.
    private func flushed(_ rig: Rig) async {
        _ = await rig.subject.select(.package("nobody"))
    }

    // MARK: - The block and the states of a choice

    @Test("a chosen effect that declares parameters is prepared with the block of their defaults, and its state lists those defaults")
    func declaredParametersArePreparedWithTheirDefaults() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        let defaults = ParameterModel(specs: EffectParameterSpec.all, restoring: [:])
        #expect(request.parameters == defaults.block)
        #expect(watcher.states.values.map(\.parameters) == [defaults.states])
        await rig.stop(run)
    }

    @Test("a chosen effect that declares no parameters is prepared with the empty block, and its state lists none")
    func undeclaredParametersArePreparedAsNone() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(request.parameters == .none)
        #expect(watcher.states.values.map(\.parameters) == [[]])
        await rig.stop(run)
    }

    @Test("an answer for the effect chosen before publishes the new choice with no parameters and no outcome, never the old ones")
    func staleAnswerShowsNoOldParameters() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.runtime.prepareRequests.waitForCount(1)  // glitch's prepare is out, and stays out

        rig.settings.holdWrites()
        let choice = Task { await rig.subject.select(other.id) }
        await rig.settings.heldRequests.waitForCount(1)  // other is chosen, and is still being remembered
        await rig.answer(1)  // glitch's answer comes back now
        await watcher.states.waitForCount(1)

        let overtaken = EffectCatalogState(entries: [bundled, glitch, other], selection: other.id, outcome: nil, parameters: [])
        #expect(watcher.states.values == [overtaken])

        rig.settings.holdWrites(false)
        rig.settings.complete(rig.settings.heldRequests.values[0])
        await rig.answer(2)
        #expect(await choice.value == .prepared)
        await watcher.states.waitForCount(2)

        let chosen = EffectCatalogState(entries: [bundled, glitch, other], selection: other.id, outcome: .prepared, parameters: [])
        #expect(watcher.states.values.last == chosen)
        #expect(rig.runtime.prepareRequests.values[1].parameters == .none)
        await rig.stop(run)
    }

    // MARK: - A listing that changes the declaration

    @Test("a package edited to declare one more parameter is prepared with the new layout, and a parameter it drops leaves the list")
    func editedDeclarationFollowsTheNewLayout() async {
        let strength = EffectParameterSpec.strength
        let rings = EffectParameterSpec.rings
        let inverted = EffectParameterSpec.inverted
        let first = EffectSource(name: "Glitch", source: "glitch v1", parameters: [strength, rings])
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(first))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let grown = [strength, rings, inverted]
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2", parameters: grown)), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        let second = await rig.answer(2)
        await watcher.states.waitForCount(2)

        let grownModel = ParameterModel(specs: grown, restoring: [:])
        #expect(second.parameters == grownModel.block)
        #expect(watcher.states.values.last?.parameters == grownModel.states)

        let dropped = [rings, inverted]
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v3", parameters: dropped)), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        let third = await rig.answer(3)
        await watcher.states.waitForCount(3)

        let droppedModel = ParameterModel(specs: dropped, restoring: [:])
        #expect(third.parameters == droppedModel.block)
        #expect(watcher.states.values.last?.parameters == droppedModel.states)
        await rig.stop(run)
    }

    @Test("a source whose label or range alone changed is prepared again, and the block it hands the runtime is unchanged")
    func labelOrRangeChangeKeepsTheBlock() async {
        let rings = EffectParameterSpec.rings
        let first = EffectSource(name: "Glitch", source: "glitch v1", parameters: [rings])
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(first))
        let watcher = rig.watch()
        let run = rig.start()
        let original = await rig.answer(1)
        await watcher.states.waitForCount(1)

        let relabelled = EffectParameterSpec(id: "rings", label: "Count", kind: .int(min: 1, max: 16, defaultValue: 4))
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v2", parameters: [relabelled])), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        let afterLabel = await rig.answer(2)
        await watcher.states.waitForCount(2)
        #expect(afterLabel.parameters == original.parameters)
        #expect(watcher.states.values.last?.parameters == ParameterModel(specs: [relabelled], restoring: [:]).states)

        let widened = EffectParameterSpec(id: "rings", label: "Count", kind: .int(min: 1, max: 32, defaultValue: 4))
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch v3", parameters: [widened])), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        let afterRange = await rig.answer(3)
        await watcher.states.waitForCount(3)
        #expect(afterRange.parameters == original.parameters)
        #expect(watcher.states.values.last?.parameters == ParameterModel(specs: [widened], restoring: [:]).states)
        await rig.stop(run)
    }

    @Test("a listing that reads the same source again prepares nothing and publishes no new state")
    func unchangedSourceChangesNothing() async {
        let rig = Rig(persisted: glitch.id, sources: Self.glitchReads(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.publish([bundled, glitch, other])
        await rig.packages.sourceRequests.waitForCount(2)
        await flushed(rig)

        #expect(rig.runtime.prepareRequests.count == 1)
        #expect(watcher.states.values.count == 1)
        await rig.stop(run)
    }

    // MARK: - A fallback to the effect over the same source

    @Test("a fallback to the bundled effect over the same declaring source prepares it once more, with the bundled defaults")
    func fallbackOverADeclaringSourcePreparesAgain() async {
        let rig = Rig(persisted: glitch.id, sources: Self.sharing(Self.declaring))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.publish([bundled, other])  // glitch is gone, and the bundled effect reads the same source
        let fallback = await rig.answer(2)
        await watcher.states.waitForCount(2)

        let defaults = ParameterModel(specs: EffectParameterSpec.all, restoring: [:])
        #expect(rig.runtime.prepareRequests.count == 2)
        #expect(fallback.parameters == defaults.block)
        let fellBack = EffectCatalogState(
            entries: [bundled, other], selection: bundled.id, outcome: .prepared, parameters: defaults.states)
        #expect(watcher.states.values.last == fellBack)
        await rig.stop(run)
    }

    @Test("a fallback to the bundled effect over the same source that declares nothing prepares nothing and only moves the selection")
    func fallbackOverAnUndeclaredSourcePreparesNothing() async {
        let plain = EffectSource(name: "Shared", source: "shared plain")
        let rig = Rig(persisted: glitch.id, sources: Self.sharing(plain))
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.publish([bundled, other])  // glitch is gone, and the bundled effect reads the same source
        await watcher.states.waitForCount(2)
        await flushed(rig)

        #expect(rig.runtime.prepareRequests.count == 1)
        let moved = EffectCatalogState(entries: [bundled, other], selection: bundled.id, outcome: .prepared, parameters: [])
        #expect(watcher.states.values.last == moved)
        await rig.stop(run)
    }
}
