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

    /// One log line per report; the shape the acceptance criteria grep for.
    public var summary: String {
        "frames=\(framesSent) received=\(framesReceived) dropped=\(framesDropped) maxGapMs=\(Int(maxGap.milliseconds.rounded())) slate=\(slateFrames)"
    }
}
