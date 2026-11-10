import Dependencies

/// `EffectRuntimeStateDataSource`: what the effect runtime remembers between its
/// calls — the compile cache, which effect `apply` runs and the parameter block that goes
/// with it, the apply callers waiting for it, and the session clock — and the transitions
/// that keep those consistent.
/// `EffectRuntimeRepository` orchestrates the compile and the render around it;
/// this holds no policy beyond the transitions, and touches no Gateway.
///
/// The live value is confined to `FrameExecutor`, so there is no lock and no actor:
/// every call here hops onto it, decides in one step, and hops back. A caller is
/// never on that executor, which is why the port is `async`. Cancelling a caller
/// cuts nothing short: a call that has been admitted answers when its step runs or
/// when the selection settles.
///
/// The rules, in the order a runtime meets them:
/// - **Tickets.** `begin` takes the next ticket. A compile settles the selection
///   only under the newest ticket, so a slow compile overtaken by a newer `begin`
///   loses ("newest wins").
/// - **The cache** is keyed by `(source, compile options)` and never by the
///   effect's name. Only a successful compile is kept, whatever its ticket.
/// - **The selection** is the effect `apply` runs. It never returns to "nothing
///   prepared". A source that does not compile is final until a newer `begin`; a
///   compile that failed for the environment's reasons (no GPU context, or the compiler
///   service failing: `ShaderDiagnostics.Cause.environment`) is not.
/// - **Waiting.** An `admit` that finds the newest compile still running parks
///   until the selection settles, and is released in arrival order.
/// - **Streaks.** A compile that failed for the environment's reasons is retried by
///   every `admit`, so a settlement says where it falls in its streak (`EffectSettlement`): the
///   caller logs the first failure and the recovery, and the rest is only counted.
/// - **Parameters.** The block belongs to the effect of the newest `begin`, which delivers
///   the first one with the selection in one step; `setParameters` replaces it for as long as that
///   effect is the newest and is dropped for any other. A block is only ever handed out together
///   with the selection it belongs to (`EffectSelection`), read in the same step that settles it,
///   so a pass never runs one effect's library with another's layout. Blocks are values: a pass
///   that has been answered keeps the one it was given, whatever is written after.
/// - **Outcomes.** The selection also carries the fingerprint of the effect it settles to, read in the
///   same step as its library, so a pass is stamped with the effect it ran and not with whichever the
///   user has picked by the time it ends. `report` queues a pass's outcome on the executor and returns;
///   the executor hands it to every stream `outcomes()` has opened. Each stream keeps the newest 64
///   outcomes it has not delivered, so a slow observer loses old outcomes and the frame path loses nothing.
public protocol EffectRuntimeState: Sendable {
    /// A `prepare` begins: takes the next ticket and makes `effect` the one that owns the
    /// parameter block, which starts as `parameters`. A cached library is selected at
    /// once (and releases the applies waiting on an overtaken compile); anything
    /// else leaves the selection waiting for the compile that only this ticket may settle.
    func begin(_ effect: EffectSource, parameters: EffectParameterBlock) async -> EffectBegin

    /// Replaces the block of `effect` when it is the effect of the newest `begin` (the compile
    /// may still be running); a write for any other effect is dropped. Returns as soon as the
    /// write is queued on the executor, which runs it in order with the other calls. A write
    /// made after `begin` has returned runs after it; one made while `begin` is still on its way
    /// to the executor may run first, and is then dropped like any write for an effect not begun.
    func setParameters(_ block: EffectParameterBlock, of effect: EffectSource)

    /// A compile ends. A success is cached whatever its ticket; the outcome becomes
    /// the selection only if no `begin` has come since.
    func settle(_ effect: EffectSource, ticket: EffectTicket, outcome: Result<any LibraryHandle, ShaderDiagnostics>) async -> EffectSettlement

    /// An `apply` begins: the pass's uniforms (and the session clock they come
    /// from), and what to run with its parameter block. When nothing has been prepared,
    /// `fallback` is asked for the effect to compile; it is not asked otherwise.
    func admit(_ context: FrameContext, output: SurfaceDescriptor, fallback: @escaping @Sendable () -> EffectSource) async -> EffectAdmission

    /// The selection once it has settled: at once, or when the newest compile does.
    /// For the `apply` that started a compile itself (`EffectAdmission.compile`).
    func selected() async -> EffectSelection

    /// A pass ended. Queues `outcome` on the executor and returns without waiting for it, as
    /// `setParameters` does, so reporting never holds up the frame path; every stream that
    /// `outcomes()` has open gets it, in the order the reports were made. The stamp is the caller's:
    /// the `fingerprint` of the `EffectSelection` the pass ran.
    func report(_ outcome: EffectPassOutcome)

    /// The outcomes reported after this call. Every call opens a stream of its own and any number may
    /// be open, each copying every outcome, so one observer cannot take another's. A stream replays
    /// nothing, keeps the newest 64 outcomes it has not yet delivered (a slow observer loses old
    /// ones, never a frame) and ends when its consumer lets go. A `report` made after this returns is
    /// delivered to the stream.
    func outcomes() -> AsyncStream<EffectPassOutcome>
}

/// What an `apply` runs once the selection has settled: the library to run or the failure
/// to answer, the parameter block of the effect that library belongs to, and what that effect
/// compiled to. They are read in one step, so the block always fits the library and the
/// fingerprint names the effect that ran, even when a newer `begin` replaced the effect between
/// the moment the `apply` was admitted and the moment its selection settled.
/// Carries a library handle, so it lives here rather than in `Entity`.
public struct EffectSelection: Sendable {
    public let result: Result<any LibraryHandle, EffectFailure>
    public let parameters: EffectParameterBlock
    /// The stamp of the pass: `EffectFingerprint.of` the effect `result` belongs to, a failed one included.
    public let fingerprint: EffectFingerprint

    public init(result: Result<any LibraryHandle, EffectFailure>, parameters: EffectParameterBlock, fingerprint: EffectFingerprint) {
        self.result = result
        self.parameters = parameters
        self.fingerprint = fingerprint
    }
}

/// How an `apply` begins. Carries a library handle, so it lives here rather than in
/// `Entity` (as `ComputePass` does); the plain values it packs are Entity types.
public enum EffectAdmission: Sendable {
    /// The selection has settled (at once, or after waiting for the newest compile):
    /// the library to run or the failure to answer with its parameter block, and the
    /// pass's uniforms. The uniforms are the admission's; the block is the settled
    /// selection's own.
    case ready(EffectSelection, EffectUniforms)
    /// Nothing is ready, but there is an effect to compile: the `fallback` while
    /// nothing was prepared, or the one whose compile failed for the environment's reasons. The
    /// caller starts that compile, settles it under `ticket` when it ends, and reads
    /// `selected()` without waiting for the compile: the selection settles when the
    /// newest effect does, which a newer `begin` may make happen first. It carries no block
    /// of its own for that reason: the effect the pass ends up running may not be this one,
    /// and `selected()` answers with the block that belongs to the one that is.
    case compile(EffectSource, EffectTicket, EffectUniforms)
}

public enum EffectRuntimeStateKey: TestDependencyKey {
    public static let testValue: any EffectRuntimeState = UnimplementedEffectRuntimeState()
}

extension DependencyValues {
    public var effectRuntimeState: any EffectRuntimeState {
        get { self[EffectRuntimeStateKey.self] }
        set { self[EffectRuntimeStateKey.self] = newValue }
    }
}

private struct UnimplementedEffectRuntimeState: EffectRuntimeState {
    func begin(_ effect: EffectSource, parameters: EffectParameterBlock) async -> EffectBegin {
        reportIssue("EffectRuntimeState.begin not implemented")
        return .compile(EffectTicket(number: 0))
    }

    func setParameters(_ block: EffectParameterBlock, of effect: EffectSource) {
        reportIssue("EffectRuntimeState.setParameters not implemented")
    }

    func settle(
        _ effect: EffectSource, ticket: EffectTicket, outcome: Result<any LibraryHandle, ShaderDiagnostics>
    ) async -> EffectSettlement {
        reportIssue("EffectRuntimeState.settle not implemented")
        return .failed(.internalError)
    }

    func admit(_ context: FrameContext, output: SurfaceDescriptor, fallback: @escaping @Sendable () -> EffectSource) async -> EffectAdmission {
        reportIssue("EffectRuntimeState.admit not implemented")
        return .ready(
            EffectSelection(result: .failure(.internalError), parameters: .none, fingerprint: Self.unstamped),
            EffectUniforms(time: 0, frameIndex: 0, resolution: SIMD2(0, 0), seed: 0))
    }

    func selected() async -> EffectSelection {
        reportIssue("EffectRuntimeState.selected not implemented")
        return EffectSelection(result: .failure(.internalError), parameters: .none, fingerprint: Self.unstamped)
    }

    func report(_ outcome: EffectPassOutcome) {
        reportIssue("EffectRuntimeState.report not implemented")
    }

    func outcomes() -> AsyncStream<EffectPassOutcome> {
        reportIssue("EffectRuntimeState.outcomes not implemented")
        return AsyncStream { $0.finish() }
    }

    /// The stamp of a selection nothing decided: the placeholders above answer with it.
    private static let unstamped = EffectFingerprint(value: String(repeating: "0", count: 16))
}
