import Domain

/// The health rules of the effect circuit breaker: counts an effect's consecutive counted failures and its
/// consecutive passes over the GPU budget, and says when one of the two streaks switches the effect off.
/// A trial, begun by `beginTrial()`, judges one pass alone; a failed trial doubles the cool-down it names.
/// Pure: it reads no clock. The cool-down it names is waited for by the session, which also owns the open state.
struct EffectHealthPolicy: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var failureThreshold = 5
        /// A pass slower than this is over budget; a pass exactly this long is not.
        var budgetSeconds = 0.1
        var budgetThreshold = 30
        var coolDown: Duration = .seconds(300)
        /// The cap for the doubling of the cool-down after failed trials.
        var maximumCoolDown: Duration = .seconds(3600)
    }

    enum Verdict: Sendable, Equatable {
        case none
        case disable(EffectDisableReason, retryAfter: Duration?)
        /// A trial pass that was within budget or reported no GPU data: the effect is back on.
        case recovered
    }

    /// `counting`: both streaks run and decide. `trial`: the next pass decides alone.
    private enum Phase: Sendable, Equatable {
        case counting
        case trial
    }

    private let configuration: Configuration
    private var phase = Phase.counting
    /// The failed trials since the last recovery. Each one doubles the cool-down of the next trial.
    private var level = 0
    private var failureStreak = 0
    private var overBudgetStreak = 0

    init(_ configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Makes the next pass a trial. Callable in any state; `level` is left as it is.
    mutating func beginTrial() {
        phase = .trial
    }

    mutating func record(_ result: Result<GPUTiming, EffectFailure>) -> Verdict {
        switch result {
        case .success(let timing):
            return recordSuccess(timing)
        case .failure(let failure):
            return recordFailure(failure)
        }
    }

    private mutating func recordSuccess(_ timing: GPUTiming) -> Verdict {
        let duration = timing.gpuEnd - timing.gpuStart
        failureStreak = 0
        // Zero or reversed timestamps mean the device reported nothing: that proves neither speed nor slowness,
        // so the over-budget streak is left as it is.
        let hasData = duration > 0
        let overBudget = hasData && duration > configuration.budgetSeconds
        switch phase {
        case .trial:
            guard overBudget else { return recoverTrial() }
            return failTrial(.overBudget)
        case .counting:
            guard hasData else { return .none }
            guard overBudget else {
                overBudgetStreak = 0
                return .none
            }
            overBudgetStreak += 1
            guard overBudgetStreak >= configuration.budgetThreshold else { return .none }
            return switchOff(.overBudget, retryAfter: configuration.coolDown)
        }
    }

    private mutating func recordFailure(_ failure: EffectFailure) -> Verdict {
        guard let kind = Self.kind(of: failure) else { return .none }
        switch phase {
        case .trial:
            return failTrial(.failure(kind))
        case .counting:
            overBudgetStreak = 0
            failureStreak += 1
            // An access revocation is final on its own: it does not wait for a streak.
            guard kind == .accessRevoked || failureStreak >= configuration.failureThreshold else { return .none }
            return switchOff(.failure(kind), retryAfter: retryAfter(for: .failure(kind), cooldown: configuration.coolDown))
        }
    }

    /// A failed trial switches the effect off at once, doubles the cool-down and hands the policy back to counting.
    private mutating func failTrial(_ reason: EffectDisableReason) -> Verdict {
        level += 1
        phase = .counting
        return switchOff(reason, retryAfter: retryAfter(for: reason, cooldown: trialCoolDown))
    }

    /// A trial that passes ends the trial with the cool-down back at its base, and hands the policy back to counting.
    private mutating func recoverTrial() -> Verdict {
        level = 0
        phase = .counting
        failureStreak = 0
        overBudgetStreak = 0
        return .recovered
    }

    /// The cool-down after `level` failed trials: doubled once per failed trial, capped at `maximumCoolDown`.
    /// The cap applies at every step, so the doubling cannot overflow.
    private var trialCoolDown: Duration {
        (0..<level).reduce(configuration.coolDown) { doubled, _ in min(doubled * 2, configuration.maximumCoolDown) }
    }

    /// Both streaks start again from zero once a verdict has been given.
    private mutating func switchOff(_ reason: EffectDisableReason, retryAfter: Duration?) -> Verdict {
        failureStreak = 0
        overBudgetStreak = 0
        return .disable(reason, retryAfter: retryAfter)
    }

    /// `nil` where a retry would hang or fault the user's call again. Otherwise the cool-down.
    private func retryAfter(for reason: EffectDisableReason, cooldown: Duration) -> Duration? {
        guard case .failure(let kind) = reason else { return cooldown }
        switch kind {
        case .timeout, .pageFault, .accessRevoked:
            return nil
        case .outOfMemory, .unknown:
            return cooldown
        }
    }

    /// The counted causes, as the record keeps them. `nil` for the causes that are the runtime's own.
    private static func kind(of failure: EffectFailure) -> EffectFailureKind? {
        switch failure {
        case .timeout:
            return .timeout
        case .pageFault:
            return .pageFault
        case .accessRevoked:
            return .accessRevoked
        case .outOfMemory:
            return .outOfMemory
        case .unknown:
            return .unknown
        case .compileFailed, .invalidResource, .internalError:
            return nil
        }
    }
}
