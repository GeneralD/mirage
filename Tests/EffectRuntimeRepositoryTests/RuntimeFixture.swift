import Dependencies
import Domain
import EffectRuntimeRepository
import EffectRuntimeStateDataSource
import TestDoubles
import TestSupport
import Testing

typealias Answer = Result<Void, EffectFailure>

/// The runtime wired to its fakes: `FakeShaderCompiler` holds every compile and
/// `FakeGPURenderer` every pass until the test completes them, and the real
/// `EffectRuntimeStateDataSourceImpl` (in-memory, no Gateway) runs its steps on a
/// `RecordingFrameExecutor` only when the test drains it. A compile an `apply`
/// starts itself runs on `workRunner`, which records when that work has finished. The subject is given no
/// executor of its own: it must reach the executor only through the state, so a
/// Repository that resolved `frameExecutor` itself would meet the unimplemented
/// default and fail. The objects are built inside `withDependencies`, so they
/// capture these fakes rather than the defaults.
struct RuntimeFixture {
    let compiler = FakeShaderCompiler()
    let renderer = FakeGPURenderer()
    let executor = RecordingFrameExecutor()
    let workRunner = RecordingWorkRunner()
    let log = RecordingLog()
    let subject: EffectRuntimeRepositoryImpl

    init(bundled: EffectSource = .bundled) {
        let compiler = compiler
        let renderer = renderer
        let executor = executor
        let workRunner = workRunner
        let log = log
        let state = withDependencies {
            $0.frameExecutor = executor
        } operation: {
            EffectRuntimeStateDataSourceImpl()
        }
        subject = withDependencies {
            $0.effectRuntimeState = state
            $0.shaderCompiler = compiler
            $0.gpuRenderer = renderer
            $0.bundledEffects = FixedBundledEffects(defaultEffect: bundled)
            $0.workRunner = workRunner
            $0.errorLog = log
            $0.developerLog = log
        } operation: {
            EffectRuntimeRepositoryImpl()
        }
    }

    /// Starts `prepare` on its own task. Nothing runs until the executor is drained.
    func prepare(_ effect: EffectSource, parameters: EffectParameterBlock = .none) -> Call {
        let subject = subject
        return Call { await subject.prepare(effect, parameters: parameters) }
    }

    /// Starts `apply` of `frame` on its own task. Nothing runs until the executor is drained.
    func apply(_ frame: Frame = Frame(index: 0)) -> Call {
        let subject = subject
        return Call { await subject.apply(input: frame.input, output: frame.output, frameContext: frame.context) }
    }

    /// Starts `apply` and returns once its first step is queued on the executor,
    /// before anything of it has run.
    func applyQueued(_ frame: Frame = Frame(index: 0)) async -> Call {
        let hops = executor.enqueued.count
        let call = apply(frame)
        await executor.enqueued.waitForCount(hops + 1)
        return call
    }

    /// Opens `outcomes()` and reads the stream on a task of its own into `OutcomeWatch.delivered`. The
    /// stream is registered through the executor, so it is open from the next drain, and replays
    /// nothing: open it before the pass it is to see.
    func watchOutcomes() -> OutcomeWatch {
        OutcomeWatch(subject.outcomes())
    }

    /// Drains the executor until `watch` has been delivered `count` outcomes, and returns what it has,
    /// or `nil` when they never came. An `apply` queues its report before it answers, but the drain that
    /// saw the answer may be over by then, so what an `apply` reported is waited for here and not in `answer`.
    @MainActor
    func delivered(_ count: Int, to watch: OutcomeWatch) async -> [EffectPassOutcome]? {
        let arrived = await tickUntil(tick: { executor.drain() }, until: { watch.delivered.count >= count })
        return arrived ? watch.delivered.values : nil
    }

    /// The first `count` outcomes `stream` delivers, waiting for them. Off the main actor, because the
    /// closure `reduce` takes is not `Sendable`.
    func read(_ count: Int, from stream: AsyncStream<EffectPassOutcome>) async -> [EffectPassOutcome] {
        await stream.prefix(count).reduce(into: [EffectPassOutcome]()) { $0.append($1) }
    }

    /// Drains the executor until `call` has answered, and returns the answer.
    @MainActor
    func answer(_ call: Call) async -> Reply {
        guard await tickUntil(tick: { executor.drain() }, until: { call.answered.count == 1 }) else { return .none }
        return Reply(await call.task.value)
    }

    /// Whether `call` is still unanswered after `ticks` drains of the executor: the
    /// negative check `tickUntil` documents. A release that should not have happened
    /// answers within a tick or two, so a call that is still waiting after the budget
    /// really was held back — unlike a count read right after one `drain()`, which
    /// cannot see an answer still on its way to the call's task.
    @MainActor
    func stillWaiting(_ call: Call, ticks: Int = 25) async -> Bool {
        await !tickUntil(ticks, tick: { executor.drain() }, until: { call.answered.count == 1 })
    }

    /// Drains the executor until `count` compiles that an `apply` started on the work
    /// runner have run to their end, which includes settling the state on the executor.
    @MainActor
    func compilesFinished(_ count: Int) async -> Bool {
        await tickUntil(tick: { executor.drain() }, until: { workRunner.finished.count >= count })
    }

    /// Drains the executor until the compiler has received its `number`-th compile (1-based).
    @MainActor
    func compileRequest(_ number: Int) async -> FakeShaderCompiler.Request? {
        guard await tickUntil(tick: { executor.drain() }, until: { compiler.requests.count >= number }) else { return nil }
        return compiler.requests.values[number - 1]
    }

    /// Drains the executor until the renderer has received its `number`-th pass (1-based).
    @MainActor
    func renderRequest(_ number: Int) async -> FakeGPURenderer.Request? {
        guard await tickUntil(tick: { executor.drain() }, until: { renderer.requests.count >= number }) else { return nil }
        return renderer.requests.values[number - 1]
    }

    /// Completes the `number`-th compile with a fresh handle and returns the handle.
    @MainActor
    func succeedCompile(_ number: Int) async throws -> FakeLibraryHandle {
        let request = try #require(await compileRequest(number), "compile \(number) was never requested")
        return try #require(compiler.succeed(request))
    }

    /// Completes the `number`-th compile with diagnostics (a broken source unless `cause` says otherwise).
    @MainActor
    func failCompile(
        _ number: Int, message: String = "effect:3:5: error: expected expression", cause: ShaderDiagnostics.Cause = .source
    ) async throws {
        let request = try #require(await compileRequest(number), "compile \(number) was never requested")
        #expect(compiler.complete(request, with: .failure(ShaderDiagnostics(message: message, code: 3, cause: cause))))
    }

    /// Completes the `number`-th compile as the compiler does when no GPU context could be made.
    @MainActor
    func failCompileForWantOfAContext(_ number: Int) async throws {
        try await failCompile(number, message: "no GPU context to compile on: noDevice", cause: .environment)
    }

    /// Prepares `effect` from scratch: its compile succeeds and the prepare answers.
    @MainActor
    func prepared(_ effect: EffectSource) async throws -> FakeLibraryHandle {
        let number = compiler.requests.count + 1
        let call = prepare(effect)
        let handle = try await succeedCompile(number)
        #expect(await answer(call) == .success)
        return handle
    }

    /// Asks `compilerMessage(of:)` for `effect` on its own task and drains the executor until it answers. A query
    /// that never answers fails the test, so a returned `nil` is the state's answer and not a missing one.
    @MainActor
    func compilerMessage(of effect: EffectSource) async throws -> String? {
        let subject = subject
        let answered = Collector<String?>()
        let query = Task {
            let message = await subject.compilerMessage(of: effect)
            answered.append(message)
            return message
        }
        let arrived = await tickUntil(tick: { executor.drain() }, until: { answered.count == 1 })
        try #require(arrived, "compilerMessage(of:) never answered")
        return await query.value
    }
}

/// An answer in a form `#expect` can compare (`Result<Void, _>` is not `Equatable`),
/// or `none` when the call never answered.
enum Reply: Equatable {
    case success
    case failure(EffectFailure)
    case none

    init(_ answer: Result<some Any, EffectFailure>) {
        switch answer {
        case .success: self = .success
        case .failure(let failure): self = .failure(failure)
        }
    }
}

/// A `prepare` or `apply` running on its own task, and its answer once it has one.
struct Call {
    let task: Task<Answer, Never>
    let answered = Collector<Answer>()

    init(_ body: @escaping @Sendable () async -> Answer) {
        let answered = answered
        task = Task {
            let answer = await body()
            answered.append(answer)
            return answer
        }
    }
}

/// An `outcomes()` stream and what its consumer, a task of its own, has read from it so far.
struct OutcomeWatch: Sendable {
    let delivered = Collector<EffectPassOutcome>()
    private let consumer: Task<Void, Never>

    init(_ stream: AsyncStream<EffectPassOutcome>) {
        let delivered = delivered
        consumer = Task {
            for await outcome in stream { delivered.append(outcome) }
        }
    }

    /// Lets go of the stream, which ends it.
    func stop() {
        consumer.cancel()
    }
}

/// One frame as the pipeline hands it to `apply`: an input and an output lease of
/// one geometry, and the frame's index and presentation time.
struct Frame: Sendable {
    static let descriptor = SurfaceDescriptor.bgra(width: 640, height: 360)

    let input: FrameRef
    let output: FrameRef
    let context: FrameContext

    init(index: UInt32, nanoseconds: UInt64 = 5_000_000_000) {
        let time = HostTimestamp(nanoseconds: nanoseconds)
        input = FrameRef(token: SurfaceToken(index: 0, generation: 1), descriptor: Self.descriptor, presentationTime: time)
        output = FrameRef(token: SurfaceToken(index: 1, generation: 1), descriptor: Self.descriptor, presentationTime: time)
        context = FrameContext(presentationTime: time, frameIndex: index)
    }
}

/// `BundledEffects` with a fixed default. Private to this suite.
struct FixedBundledEffects: BundledEffects {
    let defaultEffect: EffectSource
}

extension EffectSource {
    static let bundled = EffectSource(name: "bundled", source: "kernel void effect() { /* bundled */ }")
    static let first = EffectSource(name: "first", source: "kernel void effect() { /* first */ }")
    static let second = EffectSource(name: "second", source: "kernel void effect() { /* second */ }")
}

extension GPUTiming {
    static let sample = GPUTiming(gpuStart: 10, gpuEnd: 10.004)
}

/// The identity of a handle, compared without `!==` on `AnyObject`.
func identity(_ handle: any LibraryHandle) -> ObjectIdentifier {
    ObjectIdentifier(handle)
}
