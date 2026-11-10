import Dependencies
import Domain
import Foundation
import TestDoubles
import Testing

@Suite("FakeLogStoreGateway")
struct FakeLogStoreGatewayTests {
    // Deliberately not in timestamp order: the fake must hand entries back as given, not sorted.
    private let late = SupportLogEntry(timestamp: 200, category: "transport", message: "late")
    private let early = SupportLogEntry(timestamp: 100, category: "effects", message: "early")

    @Test("entries records the subsystem of every call, in call order")
    func queriesAreRecordedInCallOrder() throws {
        let store = FakeLogStoreGateway()
        _ = try store.entries(subsystem: "app")
        _ = try store.entries(subsystem: "extension")
        #expect(store.queries.values == ["app", "extension"])
    }

    @Test("entries hands back the entries it was made with in the order they were given")
    func entriesAreHandedBackAsGiven() throws {
        let store = FakeLogStoreGateway(entries: [late, early])
        #expect(try store.entries(subsystem: "app") == [late, early])
    }

    @Test("entries throws the failure it was made with, and still records the subsystem it was asked for")
    func failureIsThrownAndStillRecorded() {
        let store = FakeLogStoreGateway(failure: CocoaError(.fileReadUnknown))
        #expect(throws: CocoaError.self) { _ = try store.entries(subsystem: "app") }
        #expect(store.queries.values == ["app"])
    }

    @Test("logStoreGateway resolves to the substitute a test puts in its dependencies")
    func dependencyKeyResolvesTheSubstitute() {
        withDependencies {
            $0.logStoreGateway = FakeLogStoreGateway(entries: [late])
        } operation: {
            @Dependency(\.logStoreGateway) var gateway
            #expect((try? gateway.entries(subsystem: "app")) == [late])
        }
    }

    @Test("a SupportLogEntry keeps the timestamp, category and message it was made with")
    func entryKeepsItsFields() {
        let entry = SupportLogEntry(timestamp: 1.5, category: "effects", message: "loaded")
        #expect(entry.timestamp == 1.5)
        #expect(entry.category == "effects")
        #expect(entry.message == "loaded")
    }
}
