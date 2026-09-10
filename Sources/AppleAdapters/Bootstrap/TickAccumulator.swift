import GameCore

/// The fixed-timestep accumulator behind the display-link driver
/// (ADR-0007): converts host timestamps into whole 1/60 s ticks. Pure and
/// value-typed so the stall policy is unit-tested without a display link.
///
/// Policy (ADR-0007 §2–3):
/// - Elapsed wall time accumulates in tick units; whole ticks are stepped,
///   the fractional remainder carries to the next callback (a 120 Hz
///   schedule alternates 0/1 ticks, a 60 Hz one steps 1 each frame).
/// - At most `maxTicksPerCallback` ticks are stepped per callback.
/// - A RAW elapsed gap longer than `stallThresholdSeconds` (the time six
///   ticks take, with a floating-point tolerance so a six-tick frame at any
///   uptime magnitude is not misread as a stall) is a stall — debugger
///   pause, suspension, a hitch: the gap is dropped entirely and the
///   remainder reset, i.e. an implicit pause rather than a burst.
/// - Non-finite, duplicate, or backward timestamps step nothing, keep the
///   remainder, and do NOT move the accepted baseline — a later callback is
///   measured against the last ACCEPTED timestamp, so a rejected sample can
///   never manufacture elapsed time.
public struct TickAccumulator: Equatable, Sendable {
    public static let maxTicksPerCallback = 6
    public static let stallThresholdSeconds: Double =
        Double(maxTicksPerCallback) / Double(MovementRuleset.ticksPerSecond)
    /// Tolerances for binary floating point at realistic uptimes (hours):
    /// a microsecond on the raw threshold, a millionth of a tick on rounding.
    static let stallToleranceSeconds = 1e-6
    static let floatingPointEpsilonTicks = 1e-6

    public private(set) var lastTimestamp: Double?
    public private(set) var remainderTicks: Double = 0
    /// Development diagnostics: how many gaps were dropped as stalls.
    public private(set) var droppedStalls = 0

    public init() {}

    /// Forgets the previous timestamp and remainder — on suspend and on
    /// resume, so the first callback after a pause steps nothing.
    public mutating func reset() {
        lastTimestamp = nil
        remainderTicks = 0
    }

    /// Returns how many whole ticks to step for a callback at `timestamp`.
    public mutating func advance(to timestamp: Double) -> Int {
        guard timestamp.isFinite else { return 0 }
        guard let last = lastTimestamp else {
            lastTimestamp = timestamp
            return 0
        }
        let elapsed = timestamp - last
        guard elapsed > 0 else { return 0 } // duplicate/backward: baseline unchanged
        lastTimestamp = timestamp
        if elapsed > Self.stallThresholdSeconds + Self.stallToleranceSeconds {
            remainderTicks = 0
            droppedStalls += 1
            return 0
        }
        let total = remainderTicks + elapsed * Double(MovementRuleset.ticksPerSecond)
        let whole = min(Int(total + Self.floatingPointEpsilonTicks), Self.maxTicksPerCallback)
        remainderTicks = max(0, total - Double(whole))
        return whole
    }
}
