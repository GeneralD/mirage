import Domain
import EffectRuntimeRepository
import TestDoubles
import TestSupport
import Testing

/// What the Repository does with an effect's parameter block: hands the initial one over with
/// `prepare`, forwards `setParameters` to the state without preparing or compiling anything, and
/// gives the renderer the block that belongs to the library it runs. The rules of the block
/// itself (which writes land, when it is sampled) are the state's, in `ParameterBlockTests`.
@Suite("EffectRuntimeRepository parameters", .timeLimit(.minutes(1)))
@MainActor
struct EffectRuntimeParameterTests {
    private static func block(_ filler: UInt8) -> EffectParameterBlock {
        EffectParameterBlock(bytes: Array(repeating: filler, count: 48))
    }

    /// Prepares `effect` with `parameters` from scratch: its compile succeeds and the prepare answers.
    private func prepared(
        _ fixture: RuntimeFixture, _ effect: EffectSource, parameters: EffectParameterBlock
    ) async throws -> FakeLibraryHandle {
        let number = fixture.compiler.requests.count + 1
        let call = fixture.prepare(effect, parameters: parameters)
        let handle = try await fixture.succeedCompile(number)
        #expect(await fixture.answer(call) == .success)
        return handle
    }

    @Test("prepare hands the effect's initial block to the renderer along with its library, in the pass that follows")
    func prepareDeliversTheInitialBlock() async throws {
        let fixture = RuntimeFixture()
        let library = try await prepared(fixture, .first, parameters: Self.block(1))

        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply()) == .success)
        let pass = try #require(fixture.renderer.requests.values.only)
        #expect(identity(pass.library) == identity(library))
        #expect(pass.parameters == Self.block(1))
    }

    @Test("preparing a cached effect again hands over the new block too, with no compile")
    func cachedPrepareDeliversItsBlock() async throws {
        let fixture = RuntimeFixture()
        let library = try await prepared(fixture, .first, parameters: Self.block(1))

        #expect(await fixture.answer(fixture.prepare(.first, parameters: Self.block(2))) == .success)
        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply()) == .success)
        let pass = try #require(fixture.renderer.requests.values.only)
        #expect(fixture.compiler.requests.count == 1)
        #expect(identity(pass.library) == identity(library))
        #expect(pass.parameters == Self.block(2))
    }

    @Test("setParameters prepares and compiles nothing: the next apply runs the same library with the new block")
    func writePreparesNothing() async throws {
        let fixture = RuntimeFixture()
        let library = try await prepared(fixture, .first, parameters: Self.block(1))

        fixture.subject.setParameters(Self.block(2), of: .first)
        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply()) == .success)
        let pass = try #require(fixture.renderer.requests.values.only)
        #expect(identity(pass.library) == identity(library))
        #expect(pass.parameters == Self.block(2))
        #expect(fixture.compiler.requests.count == 1, "no compile for a write")
        #expect(fixture.log.messages(in: .effect) == ["effect 'first' compiled"], "and no prepare to log")
    }

    @Test("setParameters returns without waiting for the frame executor: the write is queued, and runs in order with the next apply")
    func writeDoesNotWaitForTheExecutor() async throws {
        let fixture = RuntimeFixture()
        _ = try await prepared(fixture, .first, parameters: Self.block(1))
        let queued = fixture.executor.pendingCount

        fixture.subject.setParameters(Self.block(2), of: .first)
        #expect(fixture.executor.pendingCount == queued + 1, "queued, not run: the call came back before the executor did anything")

        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply()) == .success)
        #expect(try #require(fixture.renderer.requests.values.only).parameters == Self.block(2))
    }

    @Test("a write for an effect other than the newest prepared one is dropped")
    func staleWriteIsDropped() async throws {
        let fixture = RuntimeFixture()
        _ = try await prepared(fixture, .first, parameters: Self.block(1))
        let second = try await prepared(fixture, .second, parameters: Self.block(2))

        fixture.subject.setParameters(Self.block(9), of: .first)
        fixture.renderer.respond(with: .success(.sample))
        #expect(await fixture.answer(fixture.apply()) == .success)
        let pass = try #require(fixture.renderer.requests.values.only)
        #expect(identity(pass.library) == identity(second))
        #expect(pass.parameters == Self.block(2))
    }

    @Test("a pass admitted before a write renders with the block it was admitted with, and the next apply with the new one")
    func passAdmittedBeforeAWriteKeepsItsBlock() async throws {
        let fixture = RuntimeFixture()
        _ = try await prepared(fixture, .first, parameters: Self.block(1))
        let early = fixture.apply()
        let earlyPass = try #require(await fixture.renderRequest(1))

        fixture.subject.setParameters(Self.block(2), of: .first)
        let late = fixture.apply(Frame(index: 1))
        let latePass = try #require(await fixture.renderRequest(2))

        #expect(earlyPass.parameters == Self.block(1), "still rendering with the block of its admission")
        #expect(latePass.parameters == Self.block(2))
        #expect(fixture.renderer.complete(earlyPass, with: .success(.sample)))
        #expect(fixture.renderer.complete(latePass, with: .success(.sample)))
        #expect(await fixture.answer(early) == .success)
        #expect(await fixture.answer(late) == .success)
    }

    @Test("with nothing prepared, the bundled effect renders with the empty block")
    func bundledEffectRendersWithTheEmptyBlock() async throws {
        let fixture = RuntimeFixture()
        let first = fixture.apply()
        _ = try await fixture.succeedCompile(1)
        let pass = try #require(await fixture.renderRequest(1))

        #expect(pass.parameters == .none)
        #expect(fixture.renderer.complete(pass, with: .success(.sample)))
        #expect(await fixture.answer(first) == .success)
    }

    @Test("an apply that compiled the bundled effect itself and meets a newer prepare renders the newer effect with the newer effect's block")
    func overtakenApplyRendersTheNewerEffectsBlock() async throws {
        let fixture = RuntimeFixture()
        let apply = fixture.apply()
        _ = try #require(await fixture.compileRequest(1))
        let prepare = fixture.prepare(.first, parameters: Self.block(1))
        let prepared = try await fixture.succeedCompile(2)
        #expect(await fixture.answer(prepare) == .success)

        let pass = try #require(await fixture.renderRequest(1))
        #expect(identity(pass.library) == identity(prepared))
        #expect(pass.parameters == Self.block(1), "the library's own layout, not the empty block the bundled effect would have had")
        #expect(fixture.renderer.complete(pass, with: .success(.sample)))
        #expect(await fixture.answer(apply) == .success)
    }
}

extension Array {
    /// The element of an array of exactly one, or `nil`: a pass count that is off fails the `#require`.
    fileprivate var only: Element? { count == 1 ? first : nil }
}
