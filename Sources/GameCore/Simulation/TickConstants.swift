/// The simulation's fixed timebase.
///
/// The simulation advances only by whole ticks. Wall-clock time, frame deltas, and
/// display callbacks never enter GameCore: an adapter accumulates elapsed time outside
/// and calls in with a whole number of ticks. Every duration in authoritative state is
/// therefore expressed as an integer tick count, never as seconds.
public enum TickConstants {
    /// Fixed simulation rate (plan §13.5).
    public static let ticksPerSecond: Int32 = 60
}
