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
}
