import Domain
import TestSupport
import Testing

@testable import EffectCatalogUseCase

/// A budget of 0.125 s: a power of two, so the boundary timings below are exact in binary floating point.
private let healthBudget = EffectHealthPolicy.Configuration(budgetSeconds: 0.125)
typealias HealthPass = Result<GPUTiming, EffectFailure>
private let passWithinBudget = HealthPass.success(GPUTiming(gpuStart: 0.25, gpuEnd: 0.3125))
private let passExactlyBudget = HealthPass.success(GPUTiming(gpuStart: 0.25, gpuEnd: 0.375))
private let passOverBudget = HealthPass.success(GPUTiming(gpuStart: 0.25, gpuEnd: 0.5))
private let passNoData = HealthPass.success(GPUTiming(gpuStart: 0, gpuEnd: 0))
private let passReversed = HealthPass.success(GPUTiming(gpuStart: 0.5, gpuEnd: 0.25))

/// One row of the failure table: how many passes in a row reach the verdict, and what it says.
struct HealthCase: Sendable {
    let failure: EffectFailure
    let passes: Int
    let reason: EffectFailureKind
    let retryAfter: Duration?
}

@Suite("EffectHealthPolicy", .timeLimit(.minutes(1)))
struct EffectHealthPolicyTests {
    private typealias Verdict = EffectHealthPolicy.Verdict

    private static func record(_ results: [HealthPass], into policy: inout EffectHealthPolicy) -> [Verdict] {
        results.map { policy.record($0) }
    }

    private static func repeating(_ result: HealthPass, _ count: Int) -> [HealthPass] {
        Array(repeating: result, count: count)
    }

    private static func quiet(_ count: Int) -> [Verdict] {
        Array(repeating: .none, count: count)
    }

    // MARK: - Failure streak

    @Test("four timeouts in a row are not yet a verdict, and the fifth disables the effect with no automatic retry")
    func fifthTimeoutDisables() {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(Self.repeating(.failure(.timeout), 5), into: &policy)
        #expect(verdicts == Self.quiet(4) + [Verdict.disable(.failure(.timeout), retryAfter: nil)])
    }

    @Test(
        "a counted failure disables the effect with its own reason at the streak's end, retrying only where a retry cannot hang or fault the call again",
        arguments: [
            HealthCase(failure: .timeout, passes: 5, reason: .timeout, retryAfter: nil),
            HealthCase(failure: .pageFault, passes: 5, reason: .pageFault, retryAfter: nil),
            HealthCase(failure: .accessRevoked, passes: 1, reason: .accessRevoked, retryAfter: nil),
            HealthCase(failure: .outOfMemory, passes: 5, reason: .outOfMemory, retryAfter: .seconds(300)),
            HealthCase(failure: .unknown(code: 7), passes: 5, reason: .unknown, retryAfter: .seconds(300)),
        ])
    func countedFailureDisables(testCase: HealthCase) {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(Self.repeating(.failure(testCase.failure), testCase.passes), into: &policy)
        let expected = Verdict.disable(.failure(testCase.reason), retryAfter: testCase.retryAfter)
        #expect(verdicts == Self.quiet(testCase.passes - 1) + [expected])
    }

    @Test("an access revocation disables the effect at once, even after a streak of timeouts")
    func accessRevocationIgnoresStreak() {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(Self.repeating(.failure(.timeout), 2) + [.failure(.accessRevoked)], into: &policy)
        #expect(verdicts == Self.quiet(2) + [Verdict.disable(.failure(.accessRevoked), retryAfter: nil)])
    }

    @Test(
        "a failure the runtime owns is no verdict and leaves both streaks where they were",
        arguments: [EffectFailure.compileFailed, .invalidResource, .internalError])
    func notCountedFailureKeepsStreaks(failure: EffectFailure) {
        var failureStreakPolicy = EffectHealthPolicy(healthBudget)
        let interrupted = Self.record(
            Self.repeating(.failure(.timeout), 4) + [.failure(failure)] + Self.repeating(.failure(.timeout), 1),
            into: &failureStreakPolicy)
        #expect(interrupted == Self.quiet(5) + [Verdict.disable(.failure(.timeout), retryAfter: nil)])

        var overBudgetPolicy = EffectHealthPolicy(healthBudget)
        let overBudget = Self.record(
            Self.repeating(passOverBudget, 29) + [.failure(failure)] + Self.repeating(passOverBudget, 1),
            into: &overBudgetPolicy)
        #expect(overBudget == Self.quiet(30) + [Verdict.disable(.overBudget, retryAfter: .seconds(300))])
    }

    @Test(
        "a success of any kind starts the failure count again: four timeouts, a success, four timeouts are no verdict",
        arguments: [passWithinBudget, passOverBudget, passNoData])
    func successClearsFailureStreak(success: HealthPass) {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(Self.repeating(.failure(.timeout), 4) + [success] + Self.repeating(.failure(.timeout), 4), into: &policy)
        #expect(verdicts == Self.quiet(9))
    }

    @Test("after a failure disable, the count starts again from zero")
    func failureCountRestartsAfterDisable() {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(Self.repeating(.failure(.timeout), 9), into: &policy)
        #expect(verdicts == Self.quiet(4) + [Verdict.disable(.failure(.timeout), retryAfter: nil)] + Self.quiet(4))
    }

    // MARK: - Over-budget streak

    @Test("a pass exactly at the budget is never over budget, however many times it repeats")
    func exactlyBudgetIsNeverOver() {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(Self.repeating(passExactlyBudget, 100), into: &policy)
        #expect(verdicts == Self.quiet(100))
    }

    @Test("thirty over-budget passes in a row disable the effect for the cool-down, and twenty-nine are no verdict")
    func thirtiethOverBudgetDisables() {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(Self.repeating(passOverBudget, 30), into: &policy)
        #expect(verdicts == Self.quiet(29) + [Verdict.disable(.overBudget, retryAfter: .seconds(300))])
    }

    @Test("a pass within budget starts the over-budget count again: twenty-nine over, one within, twenty-nine over are no verdict")
    func withinBudgetClearsOverBudgetStreak() {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(
            Self.repeating(passOverBudget, 29) + [passWithinBudget] + Self.repeating(passOverBudget, 29), into: &policy)
        #expect(verdicts == Self.quiet(59))
    }

    @Test("a counted failure starts the over-budget count again: twenty-nine over, a timeout, twenty-nine over are no verdict")
    func countedFailureClearsOverBudgetStreak() {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(
            Self.repeating(passOverBudget, 29) + [.failure(.timeout)] + Self.repeating(passOverBudget, 29), into: &policy)
        #expect(verdicts == Self.quiet(59))
    }

    @Test(
        "a pass with no GPU data neither counts as over budget nor clears the over-budget streak",
        arguments: [passNoData, passReversed])
    func noDataKeepsOverBudgetStreak(pass: HealthPass) {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(Self.repeating(passOverBudget, 29) + [pass] + [passOverBudget], into: &policy)
        #expect(verdicts == Self.quiet(30) + [Verdict.disable(.overBudget, retryAfter: .seconds(300))])
    }

    @Test("after an over-budget disable, the next thirty over-budget passes are counted from zero")
    func overBudgetCountRestartsAfterDisable() {
        var policy = EffectHealthPolicy(healthBudget)
        let verdicts = Self.record(Self.repeating(passOverBudget, 59), into: &policy)
        #expect(verdicts == Self.quiet(29) + [Verdict.disable(.overBudget, retryAfter: .seconds(300))] + Self.quiet(29))
    }

    // MARK: - Configuration

    @Test("the cool-down the verdicts name comes from the configuration")
    func coolDownComesFromConfiguration() {
        var policy = EffectHealthPolicy(EffectHealthPolicy.Configuration(budgetSeconds: 0.125, coolDown: .seconds(42)))
        let overBudget = Self.record(Self.repeating(passOverBudget, 30), into: &policy)
        #expect(overBudget == Self.quiet(29) + [Verdict.disable(.overBudget, retryAfter: .seconds(42))])

        var failurePolicy = EffectHealthPolicy(EffectHealthPolicy.Configuration(budgetSeconds: 0.125, coolDown: .seconds(42)))
        let outOfMemory = Self.record(Self.repeating(.failure(.outOfMemory), 5), into: &failurePolicy)
        #expect(outOfMemory == Self.quiet(4) + [Verdict.disable(.failure(.outOfMemory), retryAfter: .seconds(42))])
    }

    @Test("the default configuration gives the thresholds the health contract names")
    func defaultConfigurationNamesContractValues() {
        #expect(
            EffectHealthPolicy.Configuration()
                == EffectHealthPolicy.Configuration(
                    failureThreshold: 5, budgetSeconds: 0.1, budgetThreshold: 30,
                    coolDown: .seconds(300), maximumCoolDown: .seconds(3600)))
    }

    // MARK: - Seeded property against the table

    @Test("across seeded bursts of every kind of pass, the policy gives the verdict the table gives, pass by pass")
    func verdictsFollowTheTable() {
        forAll(seeds: Seeds.range(0..<100)) { generator in
            let seed = generator.seed
            var policy = EffectHealthPolicy(healthBudget)
            var model = HealthModel()
            for _ in 0..<20 {
                let event = HealthEvent.allCases[Int(generator.next() % UInt64(HealthEvent.allCases.count))]
                for _ in 0..<(1 + Int(generator.next() % 35)) {
                    let verdict = policy.record(event.pass)
                    let expected = model.expect(event)
                    #expect(verdict == expected, "seed \(seed): \(event) gave \(verdict), the table gives \(expected)")
                }
            }
        }
    }
}

/// The passes the property draws from: every counted cause, every cause the runtime owns, and the four kinds of success.
private enum HealthEvent: CaseIterable {
    case timeout, pageFault, accessRevoked, outOfMemory, unknown
    case compileFailed, invalidResource, internalError
    case withinBudget, exactlyBudget, overBudget, noData

    var pass: HealthPass {
        switch self {
        case .timeout: return .failure(.timeout)
        case .pageFault: return .failure(.pageFault)
        case .accessRevoked: return .failure(.accessRevoked)
        case .outOfMemory: return .failure(.outOfMemory)
        case .unknown: return .failure(.unknown(code: 1))
        case .compileFailed: return .failure(.compileFailed)
        case .invalidResource: return .failure(.invalidResource)
        case .internalError: return .failure(.internalError)
        case .withinBudget: return passWithinBudget
        case .exactlyBudget: return passExactlyBudget
        case .overBudget: return passOverBudget
        case .noData: return passNoData
        }
    }
}

/// The reference the policy is judged against: two integers and the health table, written without reading the policy.
private struct HealthModel {
    private var failures = 0
    private var overBudget = 0

    mutating func expect(_ event: HealthEvent) -> EffectHealthPolicy.Verdict {
        switch event {
        case .compileFailed, .invalidResource, .internalError:
            return .none
        case .timeout:
            return count(.timeout, retryAfter: nil)
        case .pageFault:
            return count(.pageFault, retryAfter: nil)
        case .outOfMemory:
            return count(.outOfMemory, retryAfter: .seconds(300))
        case .unknown:
            return count(.unknown, retryAfter: .seconds(300))
        case .accessRevoked:
            failures = 0
            overBudget = 0
            return .disable(.failure(.accessRevoked), retryAfter: nil)
        case .withinBudget, .exactlyBudget:
            failures = 0
            overBudget = 0
            return .none
        case .noData:
            failures = 0
            return .none
        case .overBudget:
            failures = 0
            overBudget += 1
            guard overBudget >= 30 else { return .none }
            overBudget = 0
            return .disable(.overBudget, retryAfter: .seconds(300))
        }
    }

    private mutating func count(_ kind: EffectFailureKind, retryAfter: Duration?) -> EffectHealthPolicy.Verdict {
        overBudget = 0
        failures += 1
        guard failures >= 5 else { return .none }
        failures = 0
        return .disable(.failure(kind), retryAfter: retryAfter)
    }
}
