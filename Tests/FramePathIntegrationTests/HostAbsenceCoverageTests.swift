import TestSupport
import Testing

/// The coverage half of the lease balance property (`HostAbsenceIntegrationTests`, MARK 8): every
/// seed's scenario again, in one test, to show that each absence path is actually taken. It is a
/// suite of its own because the end-to-end suite's one-minute limit guards against a hang, and
/// fifty scenarios on the main actor, next to the rest of a parallel test run with coverage on,
/// pass that minute on a loaded CI machine without hanging (#373). A suite's limit also caps its
/// tests, so a longer limit on the test alone would not take effect.
@MainActor
@Suite("Host absence, path coverage", .timeLimit(.minutes(3)))
struct HostAbsenceCoverageTests {
    @Test("across the seeds every absence path is actually taken: slate, relaunch, frame gap, real frames")
    func leaseBalancePropertyCoverage() async throws {
        var all: [HostAbsenceIntegrationTests.Coverage] = []
        for seed in Seeds.range(0..<50) { all.append(try await HostAbsenceIntegrationTests.runLeaseScenario(seed: seed)) }
        #expect(all.map(\.slateEntries).reduce(0, +) > 0, "no seed ever entered slate")
        #expect(all.map(\.relaunches).reduce(0, +) > 0, "no seed ever relaunched the host")
        #expect(all.map(\.frameGaps).reduce(0, +) > 0, "no seed ever hit the frame gap")
        #expect(all.map(\.hostLosses).reduce(0, +) > 0, "no seed ever lost the host")
        #expect(all.map(\.realFramesStreamed).reduce(0, +) > 0, "no seed ever streamed a real frame")
    }
}
