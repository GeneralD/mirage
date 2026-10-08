/// Counters the frame path keeps so the acceptance run can be read from the
/// log (`frames=<n> maxGapMs=<m>`) instead of eyeballed.
public struct PipelineStats: Sendable, Hashable {
    public var framesReceived: Int
    public var framesSent: Int
    public var framesDropped: Int
    /// Largest interval between two consecutive presentation times.
    public var maxGap: Duration
    public var lastPresentationTime: HostTimestamp?

    public init(
        framesReceived: Int = 0,
        framesSent: Int = 0,
        framesDropped: Int = 0,
        maxGap: Duration = .zero,
        lastPresentationTime: HostTimestamp? = nil
    ) {
        self.framesReceived = framesReceived
        self.framesSent = framesSent
        self.framesDropped = framesDropped
        self.maxGap = maxGap
        self.lastPresentationTime = lastPresentationTime
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
        case .dropped: framesDropped += 1
        }
    }

    /// One log line per report; the shape the acceptance criteria grep for.
    public var summary: String {
        "frames=\(framesSent) received=\(framesReceived) dropped=\(framesDropped) maxGapMs=\(Int(maxGap.milliseconds.rounded()))"
    }
}
