import Dependencies
import Domain
import TestDoubles
import Testing

@Suite("RandomSource doubles", .timeLimit(.minutes(1)))
struct RandomSourceDoublesTests {
    @Test("next(below:) draws 0 for a bound of 0 and a value in 0..<bound for every other bound")
    func protocolRange() {
        let source = SequenceRandomSource([0, 1, 6, 1_000_003, UInt64.max])
        let bounds: [UInt64] = [0, 1, 2, 10, UInt64.max]
        for bound in bounds {
            let value = source.next(below: bound)
            #expect(bound == 0 ? value == 0 : value < bound)
        }
    }

    @Test("the randomSource test value draws 0, and so does the dependency when no override is given")
    func testValueDrawsZero() {
        #expect(RandomSourceKey.testValue.next(below: 10) == 0)
        withDependencies {
            $0.context = .test
        } operation: {
            @Dependency(\.randomSource) var randomSource
            #expect(randomSource.next(below: 10) == 0)
        }
    }

    @Test("ZeroRandomSource draws 0 for the bounds 0, 1, 10 and UInt64.max")
    func zeroDrawsZero() {
        let source = ZeroRandomSource()
        #expect(source.next(below: 0) == 0)
        #expect(source.next(below: 1) == 0)
        #expect(source.next(below: 10) == 0)
        #expect(source.next(below: UInt64.max) == 0)
    }

    @Test("SequenceRandomSource returns its values in order, each reduced below the bound of its call")
    func sequenceInOrderBelowBound() {
        let source = SequenceRandomSource([7, 9])
        #expect(source.next(below: 5) == 2)
        #expect(source.next(below: 5) == 4)
    }

    @Test("SequenceRandomSource starts again from its first value once every value has been drawn")
    func sequenceStartsOver() {
        let source = SequenceRandomSource([7, 9])
        #expect(source.next(below: 5) == 2)
        #expect(source.next(below: 5) == 4)
        #expect(source.next(below: 5) == 2)
    }

    @Test("a draw with a bound of 0 returns 0 and still moves on, so the draw after it is 4, not 2")
    func zeroBoundStillAdvances() {
        let source = SequenceRandomSource([7, 9])
        #expect(source.next(below: 0) == 0)
        #expect(source.next(below: 5) == 4)
    }

    @Test("an empty SequenceRandomSource draws 0 for every bound")
    func emptySequenceDrawsZero() {
        let source = SequenceRandomSource([])
        #expect(source.next(below: 10) == 0)
        #expect(source.next(below: 0) == 0)
    }

    @Test("draws records the bound of every call in call order, a bound of 0 included")
    func drawsRecordEveryBound() {
        let source = SequenceRandomSource([7, 9])
        _ = source.next(below: 0)
        _ = source.next(below: 5)
        _ = source.next(below: 10)
        #expect(source.draws.values == [0, 5, 10])
    }
}
