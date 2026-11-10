import Domain
import Testing

@testable import SettingsUseCase

@Suite("storeSchemaStep", .timeLimit(.minutes(1)))
struct StoreSchemaPlanTests {
    @Test("a missing version stamps")
    func missingStamps() {
        #expect(storeSchemaStep(for: .missing, current: 1) == .stamp)
    }

    @Test("a version equal to the current one is left alone")
    func equalVersionLeftAlone() {
        #expect(storeSchemaStep(for: .version(1), current: 1) == .leaveAlone)
    }

    @Test("a version newer than the current one is left alone")
    func newerVersionLeftAlone() {
        #expect(storeSchemaStep(for: .version(2), current: 1) == .leaveAlone)
    }

    @Test("a version older than the current one is stamped")
    func olderVersionStamps() {
        #expect(storeSchemaStep(for: .version(1), current: 2) == .stamp)
    }

    @Test("an unreadable value is left alone")
    func unreadableLeftAlone() {
        #expect(storeSchemaStep(for: .unreadable, current: 1) == .leaveAlone)
    }
}
