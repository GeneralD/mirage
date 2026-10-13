import Dependencies

/// `EffectRuntimeStateDataSource`: what the effect runtime remembers between its
/// calls — the compile cache, which effect `apply` runs, the apply callers waiting
/// for it, and the session clock — and the transitions that keep those consistent.
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
///   compile that found no GPU context is not (`ShaderDiagnostics.Cause`).
/// - **Waiting.** An `admit` that finds the newest compile still running parks
///   until the selection settles, and is released in arrival order.
public protocol EffectRuntimeState: Sendable {
    /// A `prepare` begins: takes the next ticket. A cached library is selected at
    /// once (and releases the applies waiting on an overtaken compile); anything
    /// else leaves the selection waiting for the compile that only this ticket may settle.
    func begin(_ effect: EffectSource) async -> EffectBegin

    /// A compile ends. A success is cached whatever its ticket; the outcome becomes
    /// the selection only if no `begin` has come since.
    func settle(_ effect: EffectSource, ticket: EffectTicket, outcome: Result<any LibraryHandle, ShaderDiagnostics>) async -> EffectSettlement

    /// An `apply` begins: the pass's uniforms (and the session clock they come
    /// from), and what to run. When nothing has been prepared, `fallback` is asked
    /// for the effect to compile; it is not asked otherwise.
    func admit(_ context: FrameContext, output: SurfaceDescriptor, fallback: @escaping @Sendable () -> EffectSource) async -> EffectAdmission

    /// The selection once it has settled: at once, or when the newest compile does.
    /// For the `apply` that compiled an effect itself (`EffectAdmission.compile`).
    func selected() async -> Result<any LibraryHandle, EffectFailure>
}

/// How an `apply` begins. Carries a library handle, so it lives here rather than in
/// `Entity` (as `ComputePass` does); the plain values it packs are Entity types.
public enum EffectAdmission: Sendable {
    /// The selection has settled (at once, or after waiting for the newest compile):
    /// the library to run or the failure to answer, and the pass's uniforms.
    case ready(Result<any LibraryHandle, EffectFailure>, EffectUniforms)
    /// Nothing is ready, but there is an effect to compile: the `fallback` while
    /// nothing was prepared, or the one whose compile found no GPU context. The
    /// caller compiles it under `ticket`, settles it, then reads `selected()`.
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
    func begin(_ effect: EffectSource) async -> EffectBegin {
        reportIssue("EffectRuntimeState.begin not implemented")
        return .compile(EffectTicket(number: 0))
    }

    func settle(
        _ effect: EffectSource, ticket: EffectTicket, outcome: Result<any LibraryHandle, ShaderDiagnostics>
    ) async -> EffectSettlement {
        reportIssue("EffectRuntimeState.settle not implemented")
        return .failed(.internalError)
    }

    func admit(_ context: FrameContext, output: SurfaceDescriptor, fallback: @escaping @Sendable () -> EffectSource) async -> EffectAdmission {
        reportIssue("EffectRuntimeState.admit not implemented")
        return .ready(.failure(.internalError), EffectUniforms(time: 0, frameIndex: 0, resolution: SIMD2(0, 0), seed: 0))
    }

    func selected() async -> Result<any LibraryHandle, EffectFailure> {
        reportIssue("EffectRuntimeState.selected not implemented")
        return .failure(.internalError)
    }
}
