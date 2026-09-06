/// Movement tuning (§6.3, §7.1–§7.2). These are ruleset DATA, not hardcoded
/// constants; values below are the PROVISIONAL Movement Lab baseline and are
/// selected/tuned during M1.
public struct MovementRuleset: Codable, Equatable, Sendable {
    /// Simulation rate is fixed at 60 ticks per second (D-018).
    public static let ticksPerSecond = 60

    /// Base tank speed in subunits per second at speed level 0.
    /// Reference-derived: ~45 reference pixels/s × 64 subunits (ADR-0001).
    public var baseSpeedSubunitsPerSecond: Int

    /// Player speed multipliers per level, in permille (§7.2).
    public var speedMultipliersPermille: [Int]

    /// Enemy speed multipliers for levels -4…4, in permille (reference table,
    /// GAME_MECHANICS_SPEC §8.3; level 0 is 0.6× the player base, NOT 1.0×).
    public var enemySpeedMultipliersPermille: [Int]

    /// How long a pre-pressed turn stays buffered (§6.3).
    public var turnBufferTicks: Int

    /// Maximum travel-axis distance the tank may be nudged onto a movement
    /// lane (multiples of 512/1024 subunits) when turning perpendicular
    /// (§6.3). 256 covers every half-cell lane phase, giving reference-style
    /// instant grid turns; assistance never teleports through collision and
    /// never changes tactical speed.
    public var alignmentAssistWindowSubunits: Int

    /// Collision inset per side of the nominal 2048×2048 footprint (§6.1).
    public var collisionInsetSubunits: Int

    public init(baseSpeedSubunitsPerSecond: Int = 2880,
                speedMultipliersPermille: [Int] = [1000, 1260, 1588, 2000],
                enemySpeedMultipliersPermille: [Int] = [150, 216, 300, 432, 600, 864, 1200, 1728, 2400],
                turnBufferTicks: Int = 10,
                alignmentAssistWindowSubunits: Int = 256,
                collisionInsetSubunits: Int = 64) {
        self.baseSpeedSubunitsPerSecond = baseSpeedSubunitsPerSecond
        self.speedMultipliersPermille = speedMultipliersPermille
        self.enemySpeedMultipliersPermille = enemySpeedMultipliersPermille
        self.turnBufferTicks = turnBufferTicks
        self.alignmentAssistWindowSubunits = alignmentAssistWindowSubunits
        self.collisionInsetSubunits = collisionInsetSubunits
    }

    public static let provisional = MovementRuleset()

    /// Per-tick accumulator increment for a speed level, in 1/60000 subunit.
    /// Whole subunits are `accumulator / (1000 × ticksPerSecond)`; the
    /// remainder carries (integer accumulator, §7.1 — no drift, no floats).
    public func accumulatorIncrement(speedLevel: Int) -> Int {
        let clamped = max(0, min(speedMultipliersPermille.count - 1, speedLevel))
        return baseSpeedSubunitsPerSecond * speedMultipliersPermille[clamped]
    }

    /// AI tanks use the reference enemy speed curve (levels -4…4).
    public func enemyAccumulatorIncrement(speedLevel: Int) -> Int {
        let index = max(0, min(enemySpeedMultipliersPermille.count - 1, speedLevel + 4))
        return baseSpeedSubunitsPerSecond * enemySpeedMultipliersPermille[index]
    }

    public static let accumulatorUnitsPerSubunit = 1000 * ticksPerSecond
}
