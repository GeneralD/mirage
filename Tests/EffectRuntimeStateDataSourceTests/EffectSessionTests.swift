import Domain
import EffectRuntimeStateDataSource
import TestSupport
import Testing

/// The uniform `time` as a pure function of presentation times, over seeded runs
/// of frames: monotonic PTS within a run, restarts (index 0 again, possibly at an
/// earlier PTS), the occasional frame stamped before its session started, and a
/// first frame that is not index 0.
@Suite("EffectSession")
struct EffectSessionTests {
    /// One frame of a generated stream, with the start of the session it belongs to in the model.
    private struct Step {
        let context: FrameContext
        let sessionStart: UInt64
    }

    /// A stream of runs. Each run counts its frames from 0 and advances PTS by 0 to
    /// 100 ms per frame (0 repeats a timestamp); now and then a frame is stamped up to
    /// a second before its session started, and a new run may start before the last
    /// one ended. Unless `firstIndexIsZero`, the stream begins mid-run.
    private static func stream(_ generator: inout SeededGenerator, firstIndexIsZero: Bool) -> [Step] {
        let runs = Int.random(in: 1...4, using: &generator)
        var steps: [Step] = []
        var clock = UInt64.random(in: 1_000_000_000...(1 << 50), using: &generator)
        for run in 0..<runs {
            let firstIndex: UInt32 = run == 0 && !firstIndexIsZero ? UInt32.random(in: 1...1000, using: &generator) : 0
            let start = clock
            for offset in 0..<UInt32.random(in: 1...30, using: &generator) {
                let early = Int.random(in: 0..<10, using: &generator) == 0 && offset > 0
                let pts = early ? start - UInt64.random(in: 1...min(start, 1_000_000_000), using: &generator) : clock
                let context = FrameContext(presentationTime: HostTimestamp(nanoseconds: pts), frameIndex: firstIndex + offset)
                steps.append(Step(context: context, sessionStart: start))
                clock += UInt64.random(in: 0...100_000_000, using: &generator)
            }
            clock -= UInt64.random(in: 0...min(clock - 1, 2_000_000_000), using: &generator)
        }
        return steps
    }

    /// Feeds the stream through `EffectSession.of`, as the runtime does frame by frame.
    private static func sessions(of steps: [Step]) -> [EffectSession] {
        steps.reduce(into: [EffectSession]()) { sessions, step in
            sessions.append(EffectSession.of(step.context, after: sessions.last))
        }
    }

    @Test(
        "a session starts at frame index 0, or at the first frame when that one is not 0, and holds until the next index 0",
        arguments: Seeds.range(0..<50))
    func sessionBoundaries(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let firstIndexIsZero = generator.next().isMultiple(of: 2)
        let steps = Self.stream(&generator, firstIndexIsZero: firstIndexIsZero)
        let sessions = Self.sessions(of: steps)
        #expect(sessions.map(\.start.nanoseconds) == steps.map(\.sessionStart))
    }

    @Test("time is the seconds since the session's start, rounded once to Float, 0 at the start and never negative", arguments: Seeds.range(0..<50))
    func timeSinceStart(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let steps = Self.stream(&generator, firstIndexIsZero: true)
        for (step, session) in zip(steps, Self.sessions(of: steps)) {
            let time = session.time(at: step.context.presentationTime)
            let pts = step.context.presentationTime.nanoseconds
            let exact = pts > step.sessionStart ? Double(pts - step.sessionStart) / 1_000_000_000 : 0
            #expect(time >= 0)
            #expect(abs(Double(time) - exact) <= exact * Double(Float.ulpOfOne), "pts \(pts), start \(step.sessionStart)")
            if step.context.frameIndex == 0 { #expect(time == 0) }
        }
    }

    @Test("within a session, a later presentation time is never an earlier time", arguments: Seeds.range(0..<50))
    func monotonic(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let session = EffectSession(start: HostTimestamp(nanoseconds: UInt64.random(in: 0...(1 << 50), using: &generator)))
        let times = (0..<64).map { _ in UInt64.random(in: 0...(1 << 51), using: &generator) }.sorted()
            .map { session.time(at: HostTimestamp(nanoseconds: $0)) }
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("the uniforms of a pass: the session's time, the caller's index, the output's size in pixels, seed 0", arguments: Seeds.range(0..<20))
    func passUniforms(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let start = UInt64.random(in: 0...(1 << 40), using: &generator)
        let context = FrameContext(
            presentationTime: HostTimestamp(nanoseconds: start + UInt64.random(in: 0...(1 << 34), using: &generator)),
            frameIndex: UInt32.random(in: 0...UInt32.max, using: &generator))
        let output = SurfaceDescriptor.bgra(width: Int.random(in: 1...4096, using: &generator), height: Int.random(in: 1...4096, using: &generator))
        let session = EffectSession(start: HostTimestamp(nanoseconds: start))

        let uniforms = EffectUniforms.pass(context, in: session, output: output)
        #expect(uniforms.time == session.time(at: context.presentationTime))
        #expect(uniforms.frameIndex == context.frameIndex)
        #expect(uniforms.resolution == SIMD2(Float(output.width), Float(output.height)))
        #expect(uniforms.seed == 0)
    }
}
