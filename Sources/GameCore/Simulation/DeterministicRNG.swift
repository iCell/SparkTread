/// SplitMix64: small, fast, splittable deterministic generator. All
/// simulation randomness flows through named streams (§18.2); stream
/// positions are authoritative state (ADR-0003).
public struct SplitMix64: Codable, Equatable, Sendable {
    public private(set) var state: UInt64
    /// Number of values drawn; serialized so a restored stream continues
    /// exactly and drift is diagnosable.
    public private(set) var draws: UInt64

    public init(seed: UInt64) {
        state = seed
        draws = 0
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        draws &+= 1
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in `0..<bound` without modulo bias beyond 2^-64 scale
    /// (acceptable for gameplay; documented, deterministic).
    public mutating func next(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }
}

/// The named RNG streams. Systems MUST use their own stream so draw counts
/// in one system never shift another system's sequence.
public struct RNGStreams: Codable, Equatable, Sendable {
    public var movement: SplitMix64
    public var spawn: SplitMix64
    public var drops: SplitMix64
    public var ai: SplitMix64

    public init(seed: UInt64) {
        // Distinct derived seeds per stream from one stage seed.
        var mix = SplitMix64(seed: seed)
        movement = SplitMix64(seed: mix.next())
        spawn = SplitMix64(seed: mix.next())
        drops = SplitMix64(seed: mix.next())
        ai = SplitMix64(seed: mix.next())
    }
}
