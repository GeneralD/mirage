import Dependencies
import Domain
import EffectRuntimeStateDataSource
import TestDoubles
import TestSupport
import Testing

/// The state DataSource on a `RecordingFrameExecutor`: every call hops onto it, so
/// nothing is decided until the test drains it, and each interleaving below is
/// written down rather than waited for. The subject is built inside
/// `withDependencies`, so it captures this executor rather than the default.
struct StateFixture {
    let executor = RecordingFrameExecutor()
    let subject: EffectRuntimeStateDataSourceImpl
    /// One element per time `admit` asked for the effect to compile while nothing was prepared.
    let fallbackReads = Collector<Void>()

    init() {
        let executor = executor
        subject = withDependencies {
            $0.frameExecutor = executor
        } operation: {
            EffectRuntimeStateDataSourceImpl()
        }
    }

    // MARK: - The port's calls, started on their own task

    /// Starts `begin` on its own task. Nothing reaches the state until the executor is drained.
    func begin(_ effect: EffectSource) -> Pending<EffectBegin> {
        let subject = subject
        return Pending { await subject.begin(effect) }
    }

    func settle(
        _ effect: EffectSource, _ ticket: EffectTicket, outcome: Result<any LibraryHandle, ShaderDiagnostics>
    ) -> Pending<EffectSettlement> {
        let subject = subject
        return Pending { await subject.settle(effect, ticket: ticket, outcome: outcome) }
    }

    /// Starts `admit` for `frame`; `fallback` is the effect to compile while nothing is prepared.
    func admit(_ frame: Frame = Frame(index: 0), fallback: EffectSource = .bundled) -> Pending<EffectAdmission> {
        let subject = subject
        let reads = fallbackReads
        return Pending {
            await subject.admit(
                frame.context, output: frame.output,
                fallback: {
                    reads.append(())
                    return fallback
                })
        }
    }

    /// Starts `admit` and returns once its step is queued on the executor, before anything of
    /// it has run: calls started one after another this way reach the executor in that order,
    /// which two bare `admit`s, each on its own task, do not promise.
    func admitQueued(_ frame: Frame = Frame(index: 0), fallback: EffectSource = .bundled) async -> Pending<EffectAdmission> {
        let hops = executor.enqueued.count
        let call = admit(frame, fallback: fallback)
        await executor.enqueued.waitForCount(hops + 1)
        return call
    }

    func selected() -> Pending<Result<any LibraryHandle, EffectFailure>> {
        let subject = subject
        return Pending { await subject.selected() }
    }

    // MARK: - Running them

    /// Drains the executor until `pending` has answered, and returns the answer.
    @MainActor
    func answer<Value: Sendable>(_ pending: Pending<Value>) async throws -> Value {
        let arrived = await tickUntil(tick: { executor.drain() }, until: { pending.answered.count == 1 })
        try #require(arrived, "the call never answered")
        return await pending.task.value
    }

    /// Whether `pending` is still unanswered after `ticks` drains of the executor: the negative
    /// check `tickUntil` documents. A release that should not have happened answers within a
    /// tick or two, so a call still waiting after the budget really was held back — unlike a
    /// count read right after one `drain()`, which cannot see an answer still on its way.
    @MainActor
    func stillWaiting<Value: Sendable>(_ pending: Pending<Value>, ticks: Int = 25) async -> Bool {
        await !tickUntil(ticks, tick: { executor.drain() }, until: { pending.answered.count == 1 })
    }

    // MARK: - Compiles, from `begin` to `settle`

    /// `begin` for an effect that is not cached: the ticket its compile settles under.
    @MainActor
    func startCompile(_ effect: EffectSource) async throws -> Compile {
        let ticket = try #require(try await answer(begin(effect)).ticket, "\(effect.name) was expected to need a compile")
        return Compile(effect: effect, ticket: ticket)
    }

    /// Settles `compile` with a fresh library.
    @MainActor
    func succeed(_ compile: Compile) async throws -> Compiled {
        let library = FakeLibraryHandle(source: compile.effect.source, options: compile.effect.options)
        return Compiled(library: library, settlement: try await answer(settle(compile.effect, compile.ticket, outcome: .success(library))))
    }

    /// Settles `compile` with diagnostics of `cause`.
    @MainActor
    func fail(_ compile: Compile, cause: ShaderDiagnostics.Cause = .source) async throws -> EffectSettlement {
        let diagnostics = ShaderDiagnostics(message: "effect:3:5: error: x", code: 3, cause: cause)
        return try await answer(settle(compile.effect, compile.ticket, outcome: .failure(diagnostics)))
    }

    /// Prepares `effect` from scratch: begins it and settles a successful compile.
    @MainActor
    func prepared(_ effect: EffectSource) async throws -> FakeLibraryHandle {
        try await succeed(startCompile(effect)).library
    }
}

/// A call to the state on its own task, and its answer once it has one.
struct Pending<Value: Sendable>: Sendable {
    let task: Task<Value, Never>
    let answered = Collector<Value>()

    init(_ body: @escaping @Sendable () async -> Value) {
        let answered = answered
        task = Task {
            let value = await body()
            answered.append(value)
            return value
        }
    }
}

/// A compile in flight: what was begun, and the ticket it settles under.
struct Compile: Sendable {
    let effect: EffectSource
    let ticket: EffectTicket
}

/// A compile that succeeded, and how the state took it.
struct Compiled {
    let library: FakeLibraryHandle
    let settlement: EffectSettlement
}

/// One frame as `apply` hands it over: its index and presentation time, and the output's geometry.
struct Frame: Sendable {
    static let descriptor = SurfaceDescriptor.bgra(width: 640, height: 360)

    let context: FrameContext
    let output = Frame.descriptor

    init(index: UInt32, nanoseconds: UInt64 = 5_000_000_000) {
        context = FrameContext(presentationTime: HostTimestamp(nanoseconds: nanoseconds), frameIndex: index)
    }
}

extension EffectBegin {
    /// The ticket of the compile to run, or `nil` for a cache hit.
    var ticket: EffectTicket? {
        guard case .compile(let ticket) = self else { return nil }
        return ticket
    }
}

extension EffectAdmission {
    var uniforms: EffectUniforms {
        switch self {
        case .ready(_, let uniforms), .compile(_, _, let uniforms): uniforms
        }
    }

    /// The library an `apply` would run, or `nil` when it is told a failure or has to compile.
    var library: (any LibraryHandle)? {
        guard case .ready(.success(let library), _) = self else { return nil }
        return library
    }

    /// The failure an `apply` would answer, or `nil` when it runs a library or has to compile.
    var failure: EffectFailure? {
        guard case .ready(.failure(let failure), _) = self else { return nil }
        return failure
    }

    /// The effect to compile and its ticket, or `nil` when the selection has settled.
    var compile: Compile? {
        guard case .compile(let effect, let ticket, _) = self else { return nil }
        return Compile(effect: effect, ticket: ticket)
    }
}

extension Result where Success == any LibraryHandle, Failure == EffectFailure {
    var library: (any LibraryHandle)? { try? get() }
    var failure: EffectFailure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }
}

extension EffectSource {
    static let bundled = EffectSource(name: "bundled", source: "kernel void effect() { /* bundled */ }")
    static let first = EffectSource(name: "first", source: "kernel void effect() { /* first */ }")
    static let second = EffectSource(name: "second", source: "kernel void effect() { /* second */ }")
}

/// The identity of a handle, compared without `!==` on `AnyObject`.
func identity(_ handle: (any LibraryHandle)?) -> ObjectIdentifier? {
    handle.map { ObjectIdentifier($0) }
}
