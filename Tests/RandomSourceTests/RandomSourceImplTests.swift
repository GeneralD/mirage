import Domain
import Testing

@testable import RandomSource

@Suite("RandomSourceImpl", .timeLimit(.minutes(1)))
struct RandomSourceImplTests {
    private let source = RandomSourceImpl()

    @Test("the live source satisfies the RandomSource port")
    func conformsToThePort() {
        let port: any RandomSource = source
        #expect(port.next(below: 1) == 0)
    }

    @Test("a bound of 0 draws 0")
    func boundOfZeroDrawsZero() {
        #expect(source.next(below: 0) == 0)
    }

    @Test("a bound of 1 draws 0")
    func boundOfOneDrawsZero() {
        let draws = (0..<1000).map { _ in source.next(below: 1) }
        #expect(draws.allSatisfy { $0 == 0 })
    }

    @Test("a bound of 10 draws only values from 0 to 9 over 1000 draws")
    func boundOfTenStaysBelowTen() {
        let draws = (0..<1000).map { _ in source.next(below: 10) }
        #expect(draws.allSatisfy { $0 < 10 })
    }

    @Test("a bound of UInt64.max draws below it and does not trap over 1000 draws")
    func boundOfMaxStaysBelowMax() {
        let draws = (0..<1000).map { _ in source.next(below: UInt64.max) }
        #expect(draws.allSatisfy { $0 < UInt64.max })
    }

    @Test("a bound of 256 draws at least two different values over 1000 draws")
    func boundOfTwoFiftySixVaries() {
        let draws = Set((0..<1000).map { _ in source.next(below: 256) })
        #expect(draws.count >= 2)
    }
}
