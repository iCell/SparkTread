import Testing
import GameCore
@testable import AppleAdapters

/// ADR-0007 clock policy: whole ticks with carried remainder, a per-callback
/// cap, and suspension-sized gaps dropped instead of burst.
@Suite struct TickAccumulatorTests {
    private let frame60 = 1.0 / 60.0
    private let frame120 = 1.0 / 120.0

    @Test func firstCallbackStepsNothing() {
        var acc = TickAccumulator()
        #expect(acc.advance(to: 10.0) == 0)
        #expect(acc.advance(to: 10.0 + frame60) == 1)
    }

    @Test func sixtyHertzStepsOneTickPerFrameWithoutDrift() {
        var acc = TickAccumulator()
        _ = acc.advance(to: 0)
        var total = 0
        for i in 1...600 { total += acc.advance(to: Double(i) * frame60) }
        #expect(total == 600)
        #expect(acc.remainderTicks < 0.01)
    }

    @Test func oneTwentyHertzAlternatesAndCarriesTheRemainder() {
        var acc = TickAccumulator()
        _ = acc.advance(to: 0)
        var total = 0
        for i in 1...1200 { total += acc.advance(to: Double(i) * frame120) }
        #expect(total == 600)
    }

    @Test func gapAtTheThresholdStepsSixEvenWithAPriorRemainder() {
        var acc = TickAccumulator()
        _ = acc.advance(to: 0)
        _ = acc.advance(to: frame120) // leaves a 0.5-tick remainder
        let ticks = acc.advance(to: frame120 + TickAccumulator.stallThresholdSeconds)
        #expect(ticks == TickAccumulator.maxTicksPerCallback)
        #expect(acc.remainderTicks > 0.49 && acc.remainderTicks < 0.51) // carried, not dropped
        #expect(acc.droppedStalls == 0)
    }

    @Test func gapAboveTheThresholdIsDroppedAsAStall() {
        var acc = TickAccumulator()
        _ = acc.advance(to: 0)
        _ = acc.advance(to: frame120)
        let ticks = acc.advance(to: frame120 + TickAccumulator.stallThresholdSeconds + 0.001)
        #expect(ticks == 0)
        #expect(acc.remainderTicks == 0)
        #expect(acc.droppedStalls == 1)
        #expect(acc.advance(to: frame120 + TickAccumulator.stallThresholdSeconds + 0.001 + frame60) == 1)
    }

    @Test func nonMonotonicTimestampsStepNothingAndKeepTheRemainder() {
        var acc = TickAccumulator()
        _ = acc.advance(to: 1.0)
        _ = acc.advance(to: 1.0 + frame120)
        let remainder = acc.remainderTicks
        #expect(acc.advance(to: 0.5) == 0)
        #expect(acc.remainderTicks == remainder)
    }

    @Test func resetForgetsTheTimestampSoResumeNeverCatchesUp() {
        var acc = TickAccumulator()
        _ = acc.advance(to: 0)
        _ = acc.advance(to: frame60)
        acc.reset()
        #expect(acc.advance(to: 100) == 0)
        #expect(acc.advance(to: 100 + frame60) == 1)
    }

    /// R4-01: the raw stall comparison tolerates floating-point subtraction
    /// at realistic uptimes — a six-tick frame is never a stall.
    @Test func sixTickFrameIsNotAStallAtAnyUptime() {
        for start in [0.0, 1.0, 1000.0, 100_000.0, 3_600_000.0] {
            var acc = TickAccumulator()
            _ = acc.advance(to: start)
            #expect(acc.advance(to: start + TickAccumulator.stallThresholdSeconds) == 6, "start \(start)")
            #expect(acc.droppedStalls == 0, "start \(start)")
        }
    }

    /// R4-01: a backward timestamp is rejected WITHOUT moving the accepted
    /// baseline, so the following sample cannot manufacture elapsed time.
    @Test func backwardTimestampKeepsTheBaselineAndRecovers() {
        var acc = TickAccumulator()
        let steps = [0.0, 0.05, 0.025, 0.05].map { acc.advance(to: $0) }
        #expect(steps == [0, 3, 0, 0])
        #expect(acc.lastTimestamp == 0.05)
        #expect(acc.advance(to: 0.05 + 1.0 / 60.0) == 1)
    }

    @Test func duplicateAndNonFiniteTimestampsStepNothing() {
        var acc = TickAccumulator()
        _ = acc.advance(to: 5.0)
        _ = acc.advance(to: 5.0 + 1.0 / 120.0)
        let remainder = acc.remainderTicks
        #expect(acc.advance(to: 5.0 + 1.0 / 120.0) == 0) // duplicate
        #expect(acc.advance(to: .nan) == 0)
        #expect(acc.advance(to: .infinity) == 0)
        #expect(acc.remainderTicks == remainder)
        #expect(acc.lastTimestamp == 5.0 + 1.0 / 120.0)
    }
}
