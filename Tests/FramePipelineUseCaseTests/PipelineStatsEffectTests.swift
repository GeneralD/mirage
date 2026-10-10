import Domain
import Testing

@testable import FramePipelineUseCase

@Suite("PipelineStats effect bookkeeping")
struct PipelineStatsEffectTests {
    @Test("effect outcomes split into applied and failures by kind, and are not sends")
    func effectOutcomesSplitIntoAppliedAndFailuresByKind() {
        var stats = PipelineStats.empty
        stats.noteEffect(.success(()))
        stats.noteEffect(.failure(.timeout))
        stats.noteEffect(.failure(.timeout))
        stats.noteEffect(.failure(.unknown(code: 9)))
        #expect(stats.effectsApplied == 1)
        #expect(stats.effectsFailed == 3)
        #expect(stats.effectFailures == [.timeout: 2, .unknown(code: 9): 1])
        #expect(stats.framesSent == 0, "an effect outcome is not a send; the frame it produced is noted separately")
    }

    @Test("the effect summary aggregates the failure kinds and the cap drops")
    func effectSummaryAggregatesTheFailureKindsAndTheCapDrops() {
        var stats = PipelineStats.empty
        #expect(stats.effectSummary == "applied=0 failed=0 capDropped=0")
        stats.noteEffect(.success(()))
        stats.noteEffect(.failure(.timeout))
        stats.noteEffect(.failure(.internalError))
        stats.noteEffect(.failure(.internalError))
        stats.noteEffect(.failure(.unknown(code: -5)))
        stats.note(.dropped(.inFlightCapReached))
        stats.note(.dropped(.notConnected))
        #expect(stats.effectSummary == "applied=1 failed=4 internalError=2 timeout=1 unknown(-5)=1 capDropped=1")
    }
}
