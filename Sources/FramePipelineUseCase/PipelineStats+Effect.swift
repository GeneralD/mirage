import Domain

/// The effect stage's policy over the shared counters: how one pass is recorded and
/// how the stage reports itself once per second. It is the host pipeline's alone, so
/// it lives here; `Entity` keeps only the counters it writes.
extension PipelineStats {
    /// Effect passes that failed, of every kind.
    var effectsFailed: Int { effectFailures.values.reduce(0, +) }

    /// Records what one effect pass came back with.
    mutating func noteEffect(_ result: Result<Void, EffectFailure>) {
        switch result {
        case .success: effectsApplied += 1
        case .failure(let failure): effectFailures[failure, default: 0] += 1
        }
    }

    /// The effect stage's line, reported next to `summary`: passes applied and
    /// failed, the failures by kind (only the kinds that occurred, sorted by
    /// name) and the frames the in-flight cap dropped. Effect failures are only
    /// ever aggregated here, never logged one by one.
    var effectSummary: String {
        let kinds = effectFailures.map { "\($0.key.logName)=\($0.value)" }.sorted()
        let capDropped = dropReasons[.inFlightCapReached, default: 0]
        return (["applied=\(effectsApplied)", "failed=\(effectsFailed)"] + kinds + ["capDropped=\(capDropped)"]).joined(separator: " ")
    }
}

extension EffectFailure {
    /// The kind as one token of a log line; `unknown` keeps its raw code.
    fileprivate var logName: String {
        switch self {
        case .unknown(let code): "unknown(\(code))"
        default: "\(self)"
        }
    }
}
