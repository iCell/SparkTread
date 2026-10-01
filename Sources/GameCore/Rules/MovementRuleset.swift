/// Movement tuning (GAME_RULES §4). Ruleset DATA: speeds are exact R5
/// integers in milli-subunits per second with permille level multipliers.
public struct MovementRuleset: Codable, Equatable, Sendable {
    /// Simulation rate is fixed at 60 ticks per second.
    public static let ticksPerSecond = 60

    /// Player base speed at speed level 0: 1.92 cells/s = 1 966 080 mSU/s
    /// (GAME_RULES §4.1 R5.2: the owner's playtests of 2026-09-15 took R5's
    /// 4.8 cells/s down to 40 %).
    public var baseSpeedMilliSubunitsPerSecond: Int

    /// Player speed multipliers per level 0…3, in permille.
    public var speedMultipliersPermille: [Int]

    /// Enemy speed multipliers for levels −4…4, in permille (level 0 is
    /// 0.6× the player base).
    public var enemySpeedMultipliersPermille: [Int]

    /// How long a pre-pressed perpendicular turn stays buffered.
    public var turnBufferTicks: Int

    /// Maximum travel-axis nudge onto a half- or full-cell lane when turning
    /// perpendicular; the nudge is swept and never passes through collision.
    public var alignmentAssistWindowSubunits: Int

    /// Collision inset per side of the nominal 2048×2048 footprint.
    public var collisionInsetSubunits: Int
    /// Ice slide budget set once when a tank on ice releases or changes
    /// direction (0 disables sliding); AntiSkid never slides.
    public var iceSlideDistanceSubunits: Int

    public init(baseSpeedMilliSubunitsPerSecond: Int = 1_966_080,
                speedMultipliersPermille: [Int] = [1000, 1260, 1588, 2000],
                enemySpeedMultipliersPermille: [Int] = [150, 216, 300, 432, 600, 864, 1200, 1728, 2400],
                turnBufferTicks: Int = 10,
                alignmentAssistWindowSubunits: Int = 512,
                collisionInsetSubunits: Int = 64,
                iceSlideDistanceSubunits: Int = 1536) {
        self.baseSpeedMilliSubunitsPerSecond = baseSpeedMilliSubunitsPerSecond
        self.speedMultipliersPermille = speedMultipliersPermille
        self.enemySpeedMultipliersPermille = enemySpeedMultipliersPermille
        self.turnBufferTicks = turnBufferTicks
        self.alignmentAssistWindowSubunits = alignmentAssistWindowSubunits
        self.collisionInsetSubunits = collisionInsetSubunits
        self.iceSlideDistanceSubunits = iceSlideDistanceSubunits
    }

    public static let provisional = MovementRuleset()

    /// Per-tick accumulator increment for a player speed level; whole
    /// subunits are `accumulator / accumulatorUnitsPerSubunit` and the
    /// remainder carries (§4.1).
    public func accumulatorIncrement(speedLevel: Int) -> Int {
        let clamped = max(0, min(speedMultipliersPermille.count - 1, speedLevel))
        return baseSpeedMilliSubunitsPerSecond * speedMultipliersPermille[clamped]
    }

    /// AI tanks use the enemy speed curve (levels −4…4).
    public func enemyAccumulatorIncrement(speedLevel: Int) -> Int {
        let index = max(0, min(enemySpeedMultipliersPermille.count - 1, speedLevel + 4))
        return baseSpeedMilliSubunitsPerSecond * enemySpeedMultipliersPermille[index]
    }

    /// 1000 mSU × 1000 permille × 60 ticks.
    public static let accumulatorUnitsPerSubunit = 1000 * 1000 * ticksPerSecond

    public static let maxBaseSpeedMilliSubunitsPerSecond = 1_000_000_000
    public static let maxMultiplierPermille = 100_000
    public static let maxTicks = 216_000

    /// Array shapes, domains, and per-tick movement under the displacement
    /// cap at the fastest level. Comparisons precede multiplication.
    public func validationIssues() -> [String] {
        var issues: [String] = []
        if baseSpeedMilliSubunitsPerSecond < 1 || baseSpeedMilliSubunitsPerSecond > Self.maxBaseSpeedMilliSubunitsPerSecond {
            issues.append("base_speed_milli_subunits_per_second must be 1…\(Self.maxBaseSpeedMilliSubunitsPerSecond)")
        }
        if speedMultipliersPermille.count != 4 { issues.append("speed_multipliers_permille must have 4 entries") }
        if enemySpeedMultipliersPermille.count != 9 { issues.append("enemy_speed_multipliers_permille must have 9 entries") }
        let multipliers = speedMultipliersPermille + enemySpeedMultipliersPermille
        if multipliers.contains(where: { $0 < 1 || $0 > Self.maxMultiplierPermille }) {
            issues.append("speed multipliers must be 1…\(Self.maxMultiplierPermille) permille")
        }
        if turnBufferTicks < 0 || turnBufferTicks > Self.maxTicks { issues.append("turn_buffer_ticks must be 0…\(Self.maxTicks)") }
        if alignmentAssistWindowSubunits < 0 || alignmentAssistWindowSubunits > SpatialUnits.subunitsPerCell {
            issues.append("alignment_assist_window_subunits must be 0…\(SpatialUnits.subunitsPerCell)")
        }
        if collisionInsetSubunits < 0 || collisionInsetSubunits >= SpatialUnits.standardTankFootprintSubunits / 2 {
            issues.append("collision_inset_subunits must leave a collision box")
        }
        if iceSlideDistanceSubunits < 0 || iceSlideDistanceSubunits > 8 * SpatialUnits.subunitsPerCell {
            issues.append("ice_slide_distance_subunits must be 0…\(8 * SpatialUnits.subunitsPerCell)")
        }
        if issues.isEmpty, let fastest = multipliers.max() {
            let perTick = baseSpeedMilliSubunitsPerSecond * fastest / Self.accumulatorUnitsPerSubunit
            if perTick > SpatialUnits.maxPerTickDisplacementSubunits {
                issues.append("fastest tank exceeds the per-tick displacement cap")
            }
        }
        return issues
    }
}
