import Entity
import TestSupport
import Testing

@Suite struct SurfaceDescriptorTests {
    @Test func bgraStrideIsFourBytesPerPixel() {
        let descriptor = SurfaceDescriptor.bgra(width: 640, height: 360)
        #expect(descriptor.bytesPerRow == 2560)
        #expect(descriptor.byteCount == 2560 * 360)
        #expect(descriptor.pixelFormat == .bgra32)
    }

    @Test func geometryIgnoresTheRowStride() {
        let padded = SurfaceDescriptor(width: 1280, height: 720, pixelFormat: .bgra32, bytesPerRow: 5184)
        #expect(SurfaceDescriptor.hd720.matchesGeometry(of: padded), "the gateway may align the stride up; the picture is the same")
        #expect(!SurfaceDescriptor.hd720.matchesGeometry(of: .bgra(width: 1280, height: 721)))
        #expect(!SurfaceDescriptor.hd720.matchesGeometry(of: .bgra(width: 1281, height: 720)))
    }
}

@Suite struct PipelineStatsTests {
    @Test func receivedFramesTrackTheWidestGap() {
        var stats = PipelineStats.empty
        stats.noteReceived(at: HostTimestamp(nanoseconds: 0))
        stats.noteReceived(at: HostTimestamp(nanoseconds: 33_000_000))
        stats.noteReceived(at: HostTimestamp(nanoseconds: 133_000_000))
        stats.noteReceived(at: HostTimestamp(nanoseconds: 150_000_000))
        #expect(stats.framesReceived == 4)
        #expect(stats.maxGap == .milliseconds(100))
        #expect(stats.lastPresentationTime == HostTimestamp(nanoseconds: 150_000_000))
    }

    @Test func outcomesSplitIntoSentAndDropped() {
        var stats = PipelineStats.empty
        stats.note(.sent)
        stats.note(.dropped(.notConnected))
        stats.note(.dropped(.poolExhausted))
        #expect(stats.framesSent == 1)
        #expect(stats.framesDropped == 2)
    }

    @Test func summaryIsTheLineTheAcceptanceRunGreps() {
        var stats = PipelineStats.empty
        stats.noteReceived(at: .zero)
        stats.noteReceived(at: HostTimestamp(nanoseconds: 40_000_000))
        stats.note(.sent)
        stats.note(.dropped(.noClient))
        #expect(stats.summary == "frames=1 received=2 dropped=1 maxGapMs=40 slate=0")
    }
}

@Suite struct RetryPolicyTests {
    @Test func serviceLookUpDoublesFromAQuarterSecondUpToFive() {
        let policy = RetryPolicy.serviceLookup
        #expect(policy.delay(afterFailure: 1) == .milliseconds(250))
        #expect(policy.delay(afterFailure: 2) == .milliseconds(500))
        #expect(policy.delay(afterFailure: 3) == .seconds(1))
        #expect(policy.delay(afterFailure: 6) == .seconds(5), "capped at the maximum")
        #expect(policy.delay(afterFailure: 60) == .seconds(5), "and stays there")
    }

    @Test func anUnboundedPolicyStaysAtTheCapHoweverLongTheOutage() {
        // 2^100_000 is not a representable factor; the cap must be reached by growing, not by scaling.
        #expect(RetryPolicy.serviceLookup.delay(afterFailure: 100_000) == .seconds(5))
    }

    @Test func neverGivesUpAfterTheFirstFailure() {
        #expect(RetryPolicy.never.delay(afterFailure: 1) == nil)
    }

    @Test func boundedPoliciesStopAtMaxAttempts() {
        let policy = RetryPolicy(initialDelay: .milliseconds(10), multiplier: 1, maxDelay: .seconds(1), maxAttempts: 3)
        #expect(policy.delay(afterFailure: 1) == .milliseconds(10))
        #expect(policy.delay(afterFailure: 2) == .milliseconds(10))
        #expect(policy.delay(afterFailure: 3) == nil)
    }

    @Test func delaysNeverShrinkAndNeverExceedTheMaximum() {
        forAll { generator in
            let initial = Duration.milliseconds(Int.random(in: 1...500, using: &generator))
            let maximum = initial * Int.random(in: 1...40, using: &generator)
            let policy = RetryPolicy(
                initialDelay: initial, multiplier: Double.random(in: 1...3, using: &generator), maxDelay: maximum, maxAttempts: nil)
            let delays = (1...12).compactMap(policy.delay(afterFailure:))
            #expect(delays.count == 12, "an unbounded policy always has a next delay (seed \(generator.seed))")
            #expect(delays == delays.sorted(), "seed \(generator.seed)")
            #expect(delays.allSatisfy { $0 <= maximum }, "seed \(generator.seed)")
        }
    }
}

@Suite struct FrameRateTests {
    @Test func frameDurationIsTheReciprocal() {
        #expect(FrameRate(framesPerSecond: 10).frameDuration == .milliseconds(100))
        // 1/30 s is not a whole number of attoseconds, so the round trip is exact only to the rounding.
        let roundTrip = FrameRate.standard.frameDuration * 30
        #expect(roundTrip <= .seconds(1) && roundTrip > .seconds(1) - .nanoseconds(1))
    }

    @Test func slateTimesAdvanceByWholeFrames() {
        let base = HostTimestamp(nanoseconds: 1_000)
        let rate = FrameRate(framesPerSecond: 10)
        #expect(rate.slateTime(base: base, index: 0) == base)
        #expect(rate.slateTime(base: base, index: 3) == base.advanced(by: .milliseconds(300)))
    }
}

@Suite struct HostTimestampTests {
    @Test func ordersByNanoseconds() {
        let earlier = HostTimestamp(nanoseconds: 1)
        let later = HostTimestamp(nanoseconds: 2)
        #expect(earlier < later)
        #expect(earlier.interval(to: later) == .nanoseconds(1))
        #expect(earlier.advanced(by: .nanoseconds(1)) == later)
    }
}
