import Domain

/// The closed half of the effect circuit breaker: counts an effect's consecutive counted
/// failures and its consecutive passes over the GPU budget, and says when one of the two
/// streaks switches the effect off. Pure: it reads no clock. The cool-down it names is
/// waited for by the session, which also owns the open state.
struct EffectHealthPolicy: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var failureThreshold = 5
        /// A pass slower than this is over budget; a pass exactly this long is not.
        var budgetSeconds = 0.1
        var budgetThreshold = 30
        var coolDown: Duration = .seconds(300)
        /// The cap for the doubling of the cool-down, which comes with the trial state (#123).
        var maximumCoolDown: Duration = .seconds(3600)
    }

    enum Verdict: Sendable, Equatable {
        case none
        case disable(EffectDisableReason, retryAfter: Duration?)
        /// Not returned yet: a trial that succeeds is reported by the trial state (#123).
        case recovered
    }

    private let configuration: Configuration
    private var failureStreak = 0
    private var overBudgetStreak = 0

    init(_ configuration: Configuration = Configuration()) {
        self.configuration = configuration
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
        guard duration > 0 else { return .none }
        guard duration > configuration.budgetSeconds else {
            overBudgetStreak = 0
            return .none
        }
        overBudgetStreak += 1
        guard overBudgetStreak >= configuration.budgetThreshold else { return .none }
        return switchOff(.overBudget, retryAfter: configuration.coolDown)
    }

    private mutating func recordFailure(_ failure: EffectFailure) -> Verdict {
        guard let kind = Self.kind(of: failure) else { return .none }
        overBudgetStreak = 0
        failureStreak += 1
        // An access revocation is final on its own: it does not wait for a streak.
        guard kind == .accessRevoked || failureStreak >= configuration.failureThreshold else { return .none }
        return switchOff(.failure(kind), retryAfter: retryAfter(for: kind))
    }

    /// Both streaks start again from zero once a verdict has been given.
    private mutating func switchOff(_ reason: EffectDisableReason, retryAfter: Duration?) -> Verdict {
        failureStreak = 0
        overBudgetStreak = 0
        return .disable(reason, retryAfter: retryAfter)
    }

    /// `nil` where a retry would hang or fault the user's call again. Otherwise the cool-down.
    private func retryAfter(for kind: EffectFailureKind) -> Duration? {
        switch kind {
        case .timeout, .pageFault, .accessRevoked:
            return nil
        case .outOfMemory, .unknown:
            return configuration.coolDown
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
