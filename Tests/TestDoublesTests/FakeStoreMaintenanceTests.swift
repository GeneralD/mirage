import Domain
import TestDoubles
import Testing

@Suite("FakeStoreMaintenance", .timeLimit(.minutes(1)))
struct FakeStoreMaintenanceTests {
    @Test("nothing given is missing, and nothing is recorded")
    func nothingGiven() async {
        let maintenance = FakeStoreMaintenance()
        #expect(await maintenance.schemaVersion() == .missing)
        #expect(maintenance.stamps.count == 0)
        #expect(maintenance.resets.count == 0)
    }

    @Test("the version it was made with is the one schemaVersion answers, unreadable included")
    func madeWithVersion() async {
        #expect(await FakeStoreMaintenance(version: .version(2)).schemaVersion() == .version(2))
        #expect(await FakeStoreMaintenance(version: .unreadable).schemaVersion() == .unreadable)
    }

    @Test("a stamp is remembered and recorded, and the stamps are recorded in call order")
    func stampRemembered() async {
        let maintenance = FakeStoreMaintenance()
        await maintenance.stampSchemaVersion(1)
        await maintenance.stampSchemaVersion(2)
        #expect(await maintenance.schemaVersion() == .version(2))
        #expect(maintenance.stamps.values == [1, 2])
        #expect(maintenance.resets.count == 0)
    }

    @Test("resetAll goes back to missing and records one reset, and a stamp after it is remembered again")
    func resetGoesMissing() async {
        let maintenance = FakeStoreMaintenance(version: .version(1))
        await maintenance.resetAll()
        #expect(await maintenance.schemaVersion() == .missing)
        #expect(maintenance.resets.count == 1)
        #expect(maintenance.stamps.count == 0)
        await maintenance.stampSchemaVersion(1)
        #expect(await maintenance.schemaVersion() == .version(1))
    }
}
