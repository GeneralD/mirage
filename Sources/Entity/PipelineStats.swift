/// Counters the frame path keeps so the acceptance run can be read from the
/// log (`frames=<n> maxGapMs=<m>`) instead of eyeballed.
public struct PipelineStats: Sendable, Hashable {
    public var framesReceived: Int
    public var framesSent: Int
    public var framesDropped: Int
    /// Placeholder frames the extension emitted while the host was absent.
    public var slateFrames: Int
    /// Largest interval between two consecutive presentation times.
    public var maxGap: Duration
    public var lastPresentationTime: HostTimestamp?
    /// `framesDropped`, split by reason.
    public var dropReasons: [FrameDropReason: Int]
    /// Effect passes whose output went on to the sink (host).
    public var effectsApplied: Int
    /// Effect passes that failed, by kind; each one passed its input through (host).
    public var effectFailures: [EffectFailure: Int]

    public init(
        framesReceived: Int = 0,
        framesSent: Int = 0,
        framesDropped: Int = 0,
        slateFrames: Int = 0,
        maxGap: Duration = .zero,
        lastPresentationTime: HostTimestamp? = nil,
        dropReasons: [FrameDropReason: Int] = [:],
        effectsApplied: Int = 0,
        effectFailures: [EffectFailure: Int] = [:]
    ) {
        self.framesReceived = framesReceived
        self.framesSent = framesSent
        self.framesDropped = framesDropped
        self.slateFrames = slateFrames
        self.maxGap = maxGap
        self.lastPresentationTime = lastPresentationTime
        self.dropReasons = dropReasons
        self.effectsApplied = effectsApplied
        self.effectFailures = effectFailures
    }
}

extension PipelineStats {
    public static let empty = PipelineStats()

    /// Effect passes that failed, of every kind.
    public var effectsFailed: Int { effectFailures.values.reduce(0, +) }

    /// Records a frame arrival and widens `maxGap` when this one came late.
    public mutating func noteReceived(at presentationTime: HostTimestamp) {
        framesReceived += 1
        if let last = lastPresentationTime {
            let gap = last.interval(to: presentationTime)
            if gap > maxGap { maxGap = gap }
        }
        lastPresentationTime = presentationTime
    }

    public mutating func note(_ outcome: SendOutcome) {
        switch outcome {
        case .sent: framesSent += 1
        case .dropped(let reason):
            framesDropped += 1
            dropReasons[reason, default: 0] += 1
        }
    }

    /// Records what one effect pass came back with.
    public mutating func noteEffect(_ result: Result<Void, EffectFailure>) {
        switch result {
        case .success: effectsApplied += 1
        case .failure(let failure): effectFailures[failure, default: 0] += 1
        }
    }

    /// One log line per report; the shape the acceptance criteria grep for.
    public var summary: String {
        "frames=\(framesSent) received=\(framesReceived) dropped=\(framesDropped) maxGapMs=\(Int(maxGap.milliseconds.rounded())) slate=\(slateFrames)"
    }

    /// The effect stage's line, reported next to `summary`: passes applied and
    /// failed, the failures by kind (only the kinds that occurred, sorted by
    /// name) and the frames the in-flight cap dropped. Effect failures are only
    /// ever aggregated here, never logged one by one.
    public var effectSummary: String {
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
