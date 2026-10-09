import TestSupport
import Testing

@Suite struct SeedsTests {
    @Test func rangeListsEverySeedInOrder() {
        #expect(Seeds.range(3..<7) == [3, 4, 5, 6])
        #expect(Seeds.range(0..<50).count == 50)
        #expect(Seeds.range(0..<32) == standardSeeds)
    }

    @Test func anEmptyRangeIsNoSeeds() {
        #expect(Seeds.range(5..<5).isEmpty)
    }
}
