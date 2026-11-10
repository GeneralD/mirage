import Domain
import EffectRuntimeStateDataSource
import TestDoubles
import TestSupport
import Testing

/// The parameter block the state keeps beside the selection: delivered with `begin`, replaced by
/// `setParameters` for the newest begun effect only, copied into each admission by value, and
/// always read together with the library it belongs to. The cache key's layout is in
/// `ParameterLayoutKeyTests`.
@Suite("EffectRuntimeState parameters", .timeLimit(.minutes(1)))
@MainActor
struct ParameterBlockTests {
    /// A block no other filler equals, as long as a manifest of a few parameters.
    private static func block(_ filler: UInt8) -> EffectParameterBlock {
        EffectParameterBlock(bytes: Array(repeating: filler, count: 48))
    }

    // MARK: - Delivery with the selection

    @Test("begin delivers the effect's initial block with its selection: the first admit after the compile runs with it")
    func beginDeliversTheInitialBlock() async throws {
        let fixture = StateFixture()
        let library = try await fixture.prepared(.first, parameters: Self.block(1))

        let admission = try await fixture.answer(fixture.admit())
        #expect(identity(admission.library) == identity(library))
        #expect(admission.parameters == Self.block(1))
    }

    @Test("a cache hit hands over its block in the same step as the selection: the block of the effect it replaces goes with it")
    func cacheHitSwitchesSelectionAndBlockTogether() async throws {
        let fixture = StateFixture()
        let first = try await fixture.prepared(.first, parameters: Self.block(1))
        _ = try await fixture.prepared(.second, parameters: Self.block(2))

        #expect(try await fixture.answer(fixture.begin(.first, parameters: Self.block(3))) == .cached)
        let admission = try await fixture.answer(fixture.admit())
        #expect(identity(admission.library) == identity(first))
        #expect(admission.parameters == Self.block(3), "the block given with this begin, not the one left by either earlier effect")
    }

    @Test("an effect begun without parameters runs with the empty block, not with what the effect before it left")
    func emptyBlockReplacesTheOldOne() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.first, parameters: Self.block(1))
        _ = try await fixture.prepared(.second)

        #expect(try await fixture.answer(fixture.admit()).parameters == EffectParameterBlock.none)
    }

    @Test("the bundled fallback, which declares no parameters, runs with the empty block")
    func fallbackRunsWithTheEmptyBlock() async throws {
        let fixture = StateFixture()
        let compile = try #require(try await fixture.answer(fixture.admit()).compile)
        let compiled = try await fixture.succeed(compile)

        let selection = try await fixture.answer(fixture.selected())
        #expect(identity(selection.library) == identity(compiled.library))
        #expect(selection.parameters == EffectParameterBlock.none)
        #expect(try await fixture.answer(fixture.admit(Frame(index: 1))).parameters == EffectParameterBlock.none)
    }

    // MARK: - Writes

    @Test("setParameters replaces the block of the newest begun effect for every admit after it")
    func writeReplacesTheBlock() async throws {
        let fixture = StateFixture()
        let library = try await fixture.prepared(.first, parameters: Self.block(1))

        fixture.setParameters(Self.block(2), of: .first)
        let admission = try await fixture.answer(fixture.admit())
        #expect(identity(admission.library) == identity(library), "a write selects nothing")
        #expect(admission.parameters == Self.block(2))
        fixture.setParameters(Self.block(3), of: .first)
        #expect(try await fixture.answer(fixture.admit(Frame(index: 1))).parameters == Self.block(3), "the latest write wins")
    }

    @Test("a pass admitted before a write keeps its block, and the next admit runs with the new one")
    func admittedPassKeepsItsBlock() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.first, parameters: Self.block(1))

        let before = try await fixture.answer(fixture.admit())
        fixture.setParameters(Self.block(2), of: .first)
        let after = try await fixture.answer(fixture.admit(Frame(index: 1)))

        #expect(before.parameters == Self.block(1))
        #expect(after.parameters == Self.block(2))
    }

    @Test("setParameters returns without waiting for the executor: the write is only queued, and an admit queued behind it sees it")
    func writeIsQueuedNotAwaited() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.first, parameters: Self.block(1))
        let queued = fixture.executor.pendingCount

        fixture.setParameters(Self.block(2), of: .first)
        #expect(fixture.executor.pendingCount == queued + 1, "queued on the executor, not run on this thread")

        let admit = await fixture.admitQueued()
        #expect(admit.answered.count == 0)
        #expect(try await fixture.answer(admit).parameters == Self.block(2), "the executor runs it in order, ahead of the admit")
    }

    @Test("a write for an effect other than the newest begun one is dropped, whether it is older or was never begun")
    func staleWriteIsDropped() async throws {
        let fixture = StateFixture()
        _ = try await fixture.prepared(.first, parameters: Self.block(1))
        let second = try await fixture.prepared(.second, parameters: Self.block(2))

        fixture.setParameters(Self.block(9), of: .first)
        fixture.setParameters(Self.block(8), of: EffectSource(name: "stranger", source: "kernel void effect() { /* stranger */ }"))
        let admission = try await fixture.answer(fixture.admit())
        #expect(identity(admission.library) == identity(second))
        #expect(admission.parameters == Self.block(2))

        #expect(try await fixture.answer(fixture.begin(.first, parameters: Self.block(4))) == .cached)
        #expect(try await fixture.answer(fixture.admit(Frame(index: 1))).parameters == Self.block(4), "the dropped write left no trace")
    }

    @Test("a write for an edited source is dropped: the source is the effect, so another source is another effect")
    func writeForAnEditedSourceIsDropped() async throws {
        let fixture = StateFixture()
        let edited = EffectSource(name: "first", source: EffectSource.first.source + "\n")
        _ = try await fixture.prepared(.first, parameters: Self.block(1))
        _ = try await fixture.prepared(edited, parameters: Self.block(2))

        fixture.setParameters(Self.block(9), of: .first)
        #expect(try await fixture.answer(fixture.admit()).parameters == Self.block(2))
        fixture.setParameters(Self.block(3), of: edited)
        #expect(try await fixture.answer(fixture.admit(Frame(index: 1))).parameters == Self.block(3))
    }

    @Test("a write before anything has begun is dropped: the fallback runs with the empty block")
    func writeBeforeAnyBeginIsDropped() async throws {
        let fixture = StateFixture()
        fixture.setParameters(Self.block(9), of: .first)

        let compile = try #require(try await fixture.answer(fixture.admit()).compile)
        _ = try await fixture.succeed(compile)
        #expect(try await fixture.answer(fixture.admit(Frame(index: 1))).parameters == EffectParameterBlock.none)
    }

    @Test("a write for the effect whose compile is still running is kept and reaches the admit that waited for it")
    func writeDuringTheCompileIsKept() async throws {
        let fixture = StateFixture()
        let compile = try await fixture.startCompile(.first, parameters: Self.block(1))
        fixture.setParameters(Self.block(2), of: .first)
        let waiting = fixture.admit()
        #expect(await fixture.stillWaiting(waiting))

        let compiled = try await fixture.succeed(compile)
        let admission = try await fixture.answer(waiting)
        #expect(identity(admission.library) == identity(compiled.library))
        #expect(admission.parameters == Self.block(2), "the pass had not started, so it runs with the block current when its selection settled")
    }

    @Test("a retry of the newest effect keeps its block, and a write made before the retry is not lost")
    func retryKeepsTheBlock() async throws {
        let fixture = StateFixture()
        let compile = try await fixture.startCompile(.first, parameters: Self.block(1))
        _ = try await fixture.fail(compile, cause: .environment)
        fixture.setParameters(Self.block(2), of: .first)

        let retry = try #require(try await fixture.answer(fixture.admit()).compile)
        #expect(retry.effect == .first)
        let compiled = try await fixture.succeed(retry)
        let admission = try await fixture.answer(fixture.admit(Frame(index: 1)))
        #expect(identity(admission.library) == identity(compiled.library))
        #expect(admission.parameters == Self.block(2))
    }

    // MARK: - The block fits the library it is read with

    @Test("an admit that waits for a compile is released with the block of the effect that settles, when a newer begin overtakes it")
    func waitingAdmitIsReleasedWithTheNewerEffectsBlock() async throws {
        let fixture = StateFixture()
        let second = try await fixture.prepared(.second, parameters: Self.block(2))
        _ = try await fixture.startCompile(.first, parameters: Self.block(1))
        let waiting = fixture.admit()
        #expect(await fixture.stillWaiting(waiting))

        #expect(try await fixture.answer(fixture.begin(.second, parameters: Self.block(3))) == .cached)
        let admission = try await fixture.answer(waiting)
        #expect(identity(admission.library) == identity(second))
        #expect(admission.parameters == Self.block(3), "the layout of the library it runs, never the one it found at admission")
    }

    @Test("an admit that compiled the fallback itself is answered the block of the effect the selection settles to")
    func selectedPairsTheLibraryWithItsBlock() async throws {
        let fixture = StateFixture()
        let fallback = try #require(try await fixture.answer(fixture.admit()).compile)
        let waiting = fixture.selected()
        #expect(await fixture.stillWaiting(waiting))

        let prepared = try await fixture.prepared(.first, parameters: Self.block(1))
        let selection = try await fixture.answer(waiting)
        #expect(identity(selection.library) == identity(prepared))
        #expect(selection.parameters == Self.block(1), "not the fallback's empty block")
        #expect(try await fixture.succeed(fallback).settlement == .compiled(selected: false))
    }
}
