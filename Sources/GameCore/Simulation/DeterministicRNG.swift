/// Seedable SplitMix64 generator used for every authoritative random decision.
///
/// SplitMix64 is chosen because its state is a single `UInt64` that advances by a fixed
/// increment: the whole generator serializes into a replay as one integer, and stepping it
/// never depends on platform word size, floating point, or the standard library's global
/// randomness. It is intentionally *not* a `RandomNumberGenerator` conformance — the
/// simulation must never be able to reach a system generator by accident.
public struct DeterministicRNG: Sendable {
    /// The complete generator state. Serialize this to persist or replay a stream.
    public private(set) var state: UInt64

    /// Creates a generator positioned at an explicit state.
    public init(seed: UInt64) {
        self.state = seed
    }

    /// Advances the stream and returns the next 64 random bits.
    public mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Advances the stream and returns the next 32 random bits.
    public mutating func nextUInt32() -> UInt32 {
        UInt32(truncatingIfNeeded: nextUInt64() >> 32)
    }

    /// Returns a value in `0..<upperBound`, uniformly and without modulo bias.
    ///
    /// Uses Lemire's multiply-shift rejection: the common path costs one multiply and no
    /// division, and the rejection threshold is computed only when a draw could be biased.
    /// Rejection (rather than a plain `%`) is what keeps small enemy-choice ranges fair.
    public mutating func next(upperBound: UInt32) -> UInt32 {
        precondition(upperBound > 0, "upperBound must be positive")
        var product = UInt64(nextUInt32()) &* UInt64(upperBound)
        var low = UInt32(truncatingIfNeeded: product)
        if low < upperBound {
            let threshold = (0 &- upperBound) % upperBound
            while low < threshold {
                product = UInt64(nextUInt32()) &* UInt64(upperBound)
                low = UInt32(truncatingIfNeeded: product)
            }
        }
        return UInt32(truncatingIfNeeded: product >> 32)
    }
}

/// The named RNG streams a stage owns, derived from one world seed.
///
/// The streams are independent on purpose: adding a random draw to the AI must never shift
/// the pickup drops or the spawn table for the same seed. That property is what lets a
/// replay survive a change to an unrelated system, and it is why systems take the one
/// stream they need instead of a shared generator.
///
/// Cosmetic randomness does not belong here — presentation owns its own generator.
public struct RNGStreams: Sendable {
    /// Enemy decision making.
    public var ai: DeterministicRNG

    /// Wave composition and spawn placement.
    public var spawn: DeterministicRNG

    /// Pickup and reward drops.
    public var drop: DeterministicRNG

    /// Per-stream domain separation constants. Arbitrary but fixed forever: changing one
    /// changes every existing replay for that stream.
    private enum StreamSalt {
        static let ai: UInt64 = 0xA1A1_A1A1_0000_0001
        static let spawn: UInt64 = 0x5A5A_5A5A_0000_0002
        static let drop: UInt64 = 0xD0D0_D0D0_0000_0003
    }

    /// Derives the three streams from a single 64-bit world seed.
    public init(worldSeed: UInt64) {
        self.ai = DeterministicRNG(seed: Self.derive(worldSeed, salt: StreamSalt.ai))
        self.spawn = DeterministicRNG(seed: Self.derive(worldSeed, salt: StreamSalt.spawn))
        self.drop = DeterministicRNG(seed: Self.derive(worldSeed, salt: StreamSalt.drop))
    }

    /// Mixes seed and salt through one SplitMix64 step so that nearby world seeds still
    /// produce well-separated stream seeds.
    private static func derive(_ seed: UInt64, salt: UInt64) -> UInt64 {
        var mixer = DeterministicRNG(seed: seed ^ salt)
        return mixer.nextUInt64()
    }
}
