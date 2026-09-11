/// Pickup and timed-effect tuning (§9.3, §6.6, §9.4). Ruleset DATA, not
/// hardcoded constants. The PROVISIONAL defaults keep the M3 tuning
/// constants; two behaviours differ from the M3 slice by recorded owner
/// decision — a longer running invincibility timer is never shortened, and
/// drops appear at random cells (ADR-0010 item 7, proposed). The reference
/// game's alternatives (e.g. its 25-second invincibility refresh rule,
/// GAME_RULES §7) are expressible here without touching simulation
/// code and land only through a recorded balance decision.
public struct PickupRuleset: Codable, Equatable, Sendable {
    /// Lifetime of a spawned pickup before it vanishes.
    public var pickupLifetimeTicks: Int
    /// Avoidance grace after spawning (§9.3): not collectable yet.
    public var pickupGraceTicks: Int
    /// Armor restored by `armor_up`.
    public var armorUpAmount: Int
    /// Invincibility: if the remaining time is at or below
    /// `invincibilityRefreshBelowTicks`, the timer becomes at least
    /// `invincibilityFloorTicks`; otherwise `invincibilityExtendTicks` are
    /// added. Defaults (600/600/0) mean "refresh to 10 s".
    public var invincibilityFloorTicks: Int
    public var invincibilityRefreshBelowTicks: Int
    public var invincibilityExtendTicks: Int
    /// Base shield: additive extension with a floor (§6.6 refresh/extend).
    public var baseShieldExtendTicks: Int
    public var baseShieldFloorTicks: Int
    /// `freeze_enemy` hold duration.
    public var freezeTicks: Int
    /// `bomb` damage against every qualified active enemy.
    public var bombDamage: Int
    /// Fort-ring expiry (ADR-0010, owner decision B of 2026-09-10): when true
    /// (default) cells recorded as steel or water at activation come back as
    /// themselves; when false every unoccupied ring cell is rebuilt as brick.
    public var fortRingRestoresRecordedKinds: Bool
    /// Where kill/carrier drops appear (owner rule 2026-09-09, reference
    /// behaviour): true = a random legal cell anywhere on the map, drawn from
    /// the `drops` stream; false = the plan §9.3 text (at the defeated
    /// enemy's cell).
    public var dropsSpawnAtRandomCells: Bool

    public init(pickupLifetimeTicks: Int = 1800,
                pickupGraceTicks: Int = 45,
                armorUpAmount: Int = 2,
                invincibilityFloorTicks: Int = 600,
                invincibilityRefreshBelowTicks: Int = 600,
                invincibilityExtendTicks: Int = 0,
                baseShieldExtendTicks: Int = 600,
                baseShieldFloorTicks: Int = 1200,
                freezeTicks: Int = 480,
                bombDamage: Int = 3,
                fortRingRestoresRecordedKinds: Bool = true,
                dropsSpawnAtRandomCells: Bool = true) {
        self.pickupLifetimeTicks = pickupLifetimeTicks
        self.pickupGraceTicks = pickupGraceTicks
        self.armorUpAmount = armorUpAmount
        self.invincibilityFloorTicks = invincibilityFloorTicks
        self.invincibilityRefreshBelowTicks = invincibilityRefreshBelowTicks
        self.invincibilityExtendTicks = invincibilityExtendTicks
        self.baseShieldExtendTicks = baseShieldExtendTicks
        self.baseShieldFloorTicks = baseShieldFloorTicks
        self.freezeTicks = freezeTicks
        self.bombDamage = bombDamage
        self.fortRingRestoresRecordedKinds = fortRingRestoresRecordedKinds
        self.dropsSpawnAtRandomCells = dropsSpawnAtRandomCells
    }

    /// Longest configurable timer (one hour of ticks): keeps every timer sum
    /// far from overflow while allowing any sensible tuning.
    public static let maxTimerTicks = 216_000
    public static let maxDamage = 99

    /// Content-validation bounds (§15.3), enforced at the configuration
    /// boundary (StageLoader, sessions): durations 1…maxTimerTicks, grace
    /// inside the lifetime, damage/armor amounts 1…maxDamage, and the
    /// invincibility floor at or above its refresh line. The simulation
    /// assumes a validated ruleset and additionally saturates timer sums.
    public func validationIssues() -> [String] {
        var issues: [String] = []
        func timer(_ value: Int, _ name: String, allowZero: Bool = false) {
            if value < (allowZero ? 0 : 1) || value > Self.maxTimerTicks {
                issues.append("\(name) must be \(allowZero ? 0 : 1)…\(Self.maxTimerTicks)")
            }
        }
        timer(pickupLifetimeTicks, "pickup_lifetime_ticks")
        timer(pickupGraceTicks, "pickup_grace_ticks", allowZero: true)
        if pickupGraceTicks >= pickupLifetimeTicks { issues.append("pickup grace must end before the lifetime") }
        if armorUpAmount < 1 || armorUpAmount > Self.maxDamage { issues.append("armor_up_amount must be 1…\(Self.maxDamage)") }
        timer(invincibilityFloorTicks, "invincibility_floor_ticks")
        timer(invincibilityRefreshBelowTicks, "invincibility_refresh_below_ticks", allowZero: true)
        timer(invincibilityExtendTicks, "invincibility_extend_ticks", allowZero: true)
        if invincibilityFloorTicks < invincibilityRefreshBelowTicks {
            issues.append("invincibility floor must be at least the refresh line")
        }
        timer(baseShieldExtendTicks, "base_shield_extend_ticks")
        timer(baseShieldFloorTicks, "base_shield_floor_ticks")
        timer(freezeTicks, "freeze_ticks")
        if bombDamage < 1 || bombDamage > Self.maxDamage { issues.append("bomb_damage must be 1…\(Self.maxDamage)") }
        return issues
    }

    /// Overflow-safe timer addition (saturates at Int.max).
    private static func saturatingAdd(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int.max : sum
    }

    public static let provisional = PickupRuleset()

    /// The reference game's rule (GAME_RULES §7, id 13): remaining
    /// ≤ 12.5 s → 25 s, otherwise +12.5 s. Not the campaign default.
    public static let referenceInvincibility = PickupRuleset(
        invincibilityFloorTicks: 1500, invincibilityRefreshBelowTicks: 750,
        invincibilityExtendTicks: 750)

    /// A running timer is never shortened by a pickup: at or below the
    /// refresh line the timer becomes at least the floor, above it the
    /// extension is added (0 by default = keep the longer timer).
    public func invincibilityTicks(afterPickupWith remaining: Int) -> Int {
        remaining <= invincibilityRefreshBelowTicks
            ? max(remaining, invincibilityFloorTicks)
            : Self.saturatingAdd(remaining, invincibilityExtendTicks)
    }

    public func baseShieldTicks(afterPickupWith remaining: Int) -> Int {
        max(Self.saturatingAdd(remaining, baseShieldExtendTicks), baseShieldFloorTicks)
    }
}
