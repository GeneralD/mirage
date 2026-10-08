/// Exponential back-off for the host's service look-up: the extension process
/// only exists while a client has the camera open, so the first look-ups after
/// launch are expected to fail until Zoom (or QuickTime) selects the device.
public struct RetryPolicy: Sendable, Hashable {
    public let initialDelay: Duration
    public let multiplier: Double
    public let maxDelay: Duration
    /// `nil` retries forever.
    public let maxAttempts: Int?

    public init(initialDelay: Duration, multiplier: Double, maxDelay: Duration, maxAttempts: Int?) {
        precondition(multiplier >= 1, "back-off must not shrink")
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
    }
}

extension RetryPolicy {
    /// 250 ms doubling to 5 s, forever: the extension may appear minutes later.
    public static let serviceLookup = RetryPolicy(
        initialDelay: .milliseconds(250), multiplier: 2, maxDelay: .seconds(5), maxAttempts: nil)

    public static let never = RetryPolicy(initialDelay: .zero, multiplier: 1, maxDelay: .zero, maxAttempts: 1)

    /// The delay before attempt `attempt + 1` after `attempt` failures (1-based:
    /// after the first failure `attempt == 1`), or `nil` when the policy is
    /// exhausted and the caller should give up.
    public func delay(afterFailure attempt: Int) -> Duration? {
        precondition(attempt >= 1)
        if let maxAttempts, attempt >= maxAttempts { return nil }
        return grown(steps: attempt - 1)
    }

    /// Grows the delay one failure at a time and stops at the cap. A closed form
    /// (`initial × multiplier^(attempt − 1)`) overflows after enough failures of
    /// an unbounded policy and `Duration * Double` traps on infinity; an idle host
    /// retrying every five seconds reaches that within an hour.
    private func grown(steps: Int) -> Duration {
        (0..<steps).reduce(Swift.min(initialDelay, maxDelay)) { delay, _ in
            delay >= maxDelay ? maxDelay : Swift.min(delay * multiplier, maxDelay)
        }
    }
}
