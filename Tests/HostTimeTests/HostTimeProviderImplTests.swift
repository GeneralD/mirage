import Darwin
import Domain
import Testing

@testable import HostTime

@Suite("HostTimeProviderImpl")
struct HostTimeProviderImplTests {
    private let provider = HostTimeProviderImpl()

    @Test("a reading is positive")
    func readingIsPositive() {
        #expect(provider.now() > .zero)
    }

    @Test("two consecutive readings never go backwards")
    func readingsAreNonDecreasing() {
        let first = provider.now()
        let second = provider.now()
        #expect(second >= first)
    }

    @Test("the interval between two readings is not negative")
    func intervalIsNotNegative() {
        let first = provider.now()
        let second = provider.now()
        #expect(first.interval(to: second) >= .zero)
    }

    @Test("a reading lies on the mach uptime axis that camera timestamps use")
    func readingIsOnTheUptimeAxis() {
        // Bracketing with the raw clock pins the axis: CLOCK_REALTIME or
        // CLOCK_MONOTONIC (which counts sleep) would fall outside the bracket.
        let before = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let reading = provider.now().nanoseconds
        let after = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        #expect(before <= reading)
        #expect(reading <= after)
    }
}
