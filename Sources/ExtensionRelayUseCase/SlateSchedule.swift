import Domain

/// The phase of the extension's output while the host may be absent, as a pure
/// value type. It owns the one invariant the stream needs: every presentation
/// time handed out (real or slate) is strictly greater than the one before.
///
/// - `live`: real host frames flow. `lastEmitted` is the newest PTS admitted.
/// - `slate`: the host is gone and placeholder frames are synthesised at
///   `base + next x frameDuration`.
public struct SlateSchedule: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        case live(lastEmitted: HostTimestamp?)
        case slate(base: HostTimestamp, next: Int, lastEmitted: HostTimestamp)
    }

    /// What to do with a real frame that arrived. Relay it at `retimed(_:)`.
    public enum Admission: Sendable, Hashable {
        /// Relay it; the phase stays live.
        case relay
        /// Relay it, after leaving slate (the phase is already live again).
        case resume
        /// Its (shifted) PTS does not advance past the last one emitted: drop it.
        case dropNonMonotonic
    }

    public let frameRate: FrameRate
    public private(set) var phase: Phase = .live(lastEmitted: nil)
    /// Nanoseconds added to every real PTS so it clears the slate PTS handed out
    /// while the host was away. Slate PTS tracks wall-clock time, while a real
    /// frame carries its (older) capture time; without the shift a camera whose
    /// latency exceeds a frame would stay behind the slate for good. Set when a
    /// real frame ends a slate episode; kept until the next one.
    public private(set) var shift: UInt64 = 0

    public init(frameRate: FrameRate) {
        self.frameRate = frameRate
    }

    public var isSlate: Bool {
        guard case .slate = phase else { return false }
        return true
    }

    /// The newest PTS emitted in either phase.
    public var lastEmitted: HostTimestamp? {
        switch phase {
        case .live(let last): last
        case .slate(_, _, let last): last
        }
    }

    /// Where a slate episode starting at `hostNow` would begin: never behind the
    /// last emitted PTS. `nil` while already in slate.
    public func slateBase(hostNow: HostTimestamp) -> HostTimestamp? {
        guard case .live(let last) = phase else { return nil }
        return last.map { max(hostNow, $0.advanced(by: frameRate.frameDuration)) } ?? hostNow
    }

    /// Enters slate at `base` (from `slateBase`). Ignored when already in slate.
    public mutating func enterSlate(base: HostTimestamp) {
        guard case .live(let last) = phase else { return }
        phase = .slate(base: base, next: 0, lastEmitted: last ?? base)
    }

    /// The PTS of the next slate frame, which counts as emitted. `nil` while live.
    public mutating func nextSlateTime() -> HostTimestamp? {
        guard case .slate(let base, let next, _) = phase else { return nil }
        let time = frameRate.slateTime(base: base, index: next)
        phase = .slate(base: base, next: next + 1, lastEmitted: time)
        return time
    }

    /// The PTS a real frame is emitted with: its own plus the current `shift`.
    public func retimed(_ time: HostTimestamp) -> HostTimestamp {
        HostTimestamp(nanoseconds: time.nanoseconds &+ shift)
    }

    /// Judges a real frame; an admitted one becomes the newest emitted PTS (at
    /// `retimed`). The first real frame in slate always resumes: the shift is
    /// recomputed from that frame so it lands just above the last slate PTS.
    public mutating func admit(_ time: HostTimestamp) -> Admission {
        switch phase {
        case .live(let last):
            let shifted = retimed(time)
            guard last.map({ shifted > $0 }) ?? true else { return .dropNonMonotonic }
            phase = .live(lastEmitted: shifted)
            return .relay
        case .slate(_, _, let last):
            shift = time > last ? 0 : last.nanoseconds - time.nanoseconds + 1
            phase = .live(lastEmitted: retimed(time))
            return .resume
        }
    }

    /// Forgets everything: the next run starts from nothing.
    public mutating func reset() {
        phase = .live(lastEmitted: nil)
        shift = 0
    }
}
