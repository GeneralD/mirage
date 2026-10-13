/// Which `prepare` a compile belongs to. The effect runtime's state hands one out
/// for every `prepare`, and only the newest may settle the selection — "newest
/// wins". The number only orders tickets; it carries no other meaning.
public struct EffectTicket: Sendable, Hashable {
    public let number: Int

    public init(number: Int) {
        self.number = number
    }
}

/// How a `prepare` begins: the effect was compiled before, or it must be compiled now.
public enum EffectBegin: Sendable, Hashable {
    /// Same source, same options as an earlier successful compile: its library is the
    /// selection at once and there is nothing to compile.
    case cached
    /// Not compiled yet: the caller compiles it under `ticket` and settles the outcome with it.
    case compile(EffectTicket)
}

/// How a compile ended, as the effect runtime's state took it.
public enum EffectSettlement: Sendable, Hashable {
    /// The compile produced a library, which is cached whatever its ticket.
    /// `selected` is `false` when a newer `prepare` came since: the library never
    /// becomes the effect `apply` runs. `afterFailures` is how many compiles of this
    /// effect in a row found no GPU context before this one: non-zero only for the
    /// success that ends such a streak and is selected (the recovery, which is news).
    case compiled(selected: Bool, afterFailures: Int = 0)
    /// The compile failed, and this is what its own caller is told: `.compileFailed`
    /// for a source that does not compile, `.internalError` when no GPU context
    /// could be made (`ShaderDiagnostics.Cause`). Every `apply` retries the latter,
    /// so `attempt` is this failure's 1-based place in its streak of consecutive
    /// GPU-context failures of the newest effect: attempt 1 is news, the rest only
    /// counts. It is 1 for a source that does not compile and for a compile that a
    /// newer `prepare` overtook.
    case failed(EffectFailure, attempt: Int = 1)
}
