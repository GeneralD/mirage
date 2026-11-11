import Domain
import TestDoubles
import TestSupport
import Testing

/// What a parameter does on the frame path, on the loopback with the real catalog and runtime (epic #42's parameters,
/// `docs/hackathon/mvp-cd/specs/parameters.md`, Flow of a value and Binding): a value set through the catalog is in the
/// block of the next frame the runtime admits, and a pass keeps the block it was admitted with. Each test is one spec
/// sentence, judged on the block of the pass the fake GPU committed.
///
/// Nothing here sleeps or reads a clock: the host's executor is pumped by `tickUntil`, and the state a set publishes is
/// waited for by what it shows, never by time.
@MainActor
@Suite("Parameters through the loopback", .timeLimit(.minutes(1)))
struct ParameterIntegrationTests {
    @Test("the first pass of a chosen package carries the defaults: strength 0.5 and mode Soft")
    func theFirstPassCarriesTheDefaults() async throws {
        let session = try await ParameterSession.start()
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)

        await session.drawFrame()

        let pass = try session.lastPass()
        #expect(pass.parameters.bytes == Tuner.block(strength: Tuner.halfStrength, mode: Tuner.softMode))
        try await session.finish()
    }

    @Test("a value set after a frame reaches the next admitted frame, and the earlier pass keeps its block")
    func aSetValueReachesTheNextAdmittedFrame() async throws {
        let session = try await ParameterSession.start()
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)
        await session.drawFrame()

        await session.set("strength", to: .float(0.75))
        // The state is published before the runtime is written to, so it does not show that the block arrived: the frame does.
        #expect(
            await session.rig.pumpHost(until: { Self.value(of: "strength", in: session.side.states.last) == .float(0.75) }),
            "the panel's state shows 0.75")
        await session.drawFrame()

        let passes = session.passes
        #expect(passes.count == 2)
        #expect(passes[1].parameters.bytes == Tuner.block(strength: Tuner.threeQuartersStrength, mode: Tuner.softMode))
        #expect(passes[0].parameters.bytes == Tuner.block(strength: Tuner.halfStrength, mode: Tuner.softMode), "the earlier pass keeps its block")
        try await session.finish()
    }

    @Test("changing a value compiles nothing again")
    func changingAValueCompilesNothing() async throws {
        let session = try await ParameterSession.start()
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)
        let compiles = session.rig.host.shaders.calls.count

        await session.set("strength", to: .float(0.75))
        #expect(await session.rig.pumpHost(until: { Self.value(of: "strength", in: session.side.states.last) == .float(0.75) }))
        await session.drawFrame()

        #expect(session.rig.host.shaders.calls.count == compiles, "the value went to the block, not to the compiler")
        #expect(try session.lastPass().parameters.bytes == Tuner.block(strength: Tuner.threeQuartersStrength, mode: Tuner.softMode))
        try await session.finish()
    }

    @Test("a choice is written as its index into the field the shader reads, from the next frame")
    func aChoiceIsWrittenAsItsIndex() async throws {
        let session = try await ParameterSession.start()
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)

        await session.set("mode", to: .choice(1))
        #expect(
            await session.rig.pumpHost(until: { Self.value(of: "mode", in: session.side.states.last) == .choice(1) }),
            "the panel's state shows Hard")
        await session.drawFrame()

        #expect(try session.lastPass().parameters.bytes == Tuner.block(strength: Tuner.halfStrength, mode: Tuner.hardMode))
        try await session.finish()
    }

    @Test("each pass carries the value its frame was admitted with, whatever is set after it")
    func eachPassKeepsTheValueItWasAdmittedWith() async throws {
        let session = try await ParameterSession.start()
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)

        await session.set("strength", to: .float(0.25))
        await session.drawFrame()
        await session.set("strength", to: .float(1.0))
        await session.drawFrame()

        let passes = session.passes
        #expect(passes.count == 2)
        #expect(passes[0].parameters.bytes == Tuner.block(strength: Tuner.quarterStrength, mode: Tuner.softMode), "0.25 at its admission")
        #expect(passes[1].parameters.bytes == Tuner.block(strength: Tuner.fullStrength, mode: Tuner.softMode), "1.0 at its admission")
        try await session.finish()
    }

    @Test("resetting the parameters puts the defaults into the next frame's block")
    func resettingPutsTheDefaultsIntoTheNextFrame() async throws {
        let session = try await ParameterSession.start()
        #expect(await session.install())
        #expect(await session.rig.choose(Tuner.id) == .prepared)
        await session.set("strength", to: .float(0.75))
        await session.set("mode", to: .choice(1))
        #expect(
            await session.rig.pumpHost(until: { Self.value(of: "mode", in: session.side.states.last) == .choice(1) }),
            "the panel's state shows Hard before the reset")

        await session.resetParameters()
        #expect(
            await session.rig.pumpHost(until: {
                Self.value(of: "strength", in: session.side.states.last) == .float(0.5)
                    && Self.value(of: "mode", in: session.side.states.last) == .choice(0)
            }),
            "the panel's state shows the defaults")
        await session.drawFrame()

        #expect(try session.lastPass().parameters.bytes == Tuner.block(strength: Tuner.halfStrength, mode: Tuner.softMode))
        try await session.finish()
    }

    /// The value the state shows for the parameter `id`, or nil when the state lists no such parameter.
    private static func value(of id: String, in state: EffectCatalogState?) -> EffectParameterValue? {
        state?.parameters.first(where: { $0.spec.id == id })?.value
    }
}
