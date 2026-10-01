/// Pickup and timed-effect tuning (GAME_RULES §10). Ruleset DATA.
public struct PickupRuleset: Codable, Equatable, Sendable {
    /// Lifetime of a placed pickup (critical pickups never expire).
    public var pickupLifetimeTicks: Int
    /// Final stretch of the lifetime that blinks (presentation reads it).
    public var pickupBlinkTicks: Int
    /// Avoidance window when a hidden pickup is revealed under a tank.
    public var revealGraceTicks: Int
    /// Armor restored by `armor_up`.
    public var armorUpAmount: Int
    /// Invincibility: at or below `invincibilityRefreshBelowTicks` the timer
    /// becomes at least `invincibilityFloorTicks`; above it the extension
    /// is added (0 = a longer timer is kept as it is).
    public var invincibilityFloorTicks: Int
    public var invincibilityRefreshBelowTicks: Int
    public var invincibilityExtendTicks: Int
    /// Flag On Guard: remaining = max(remaining + extend, floor).
    public var baseShieldExtendTicks: Int
    public var baseShieldFloorTicks: Int
    /// Hold Enemy duration.
    public var freezeTicks: Int

    public init(pickupLifetimeTicks: Int = 1800,
                pickupBlinkTicks: Int = 300,
                revealGraceTicks: Int = 90,
                armorUpAmount: Int = 2,
                invincibilityFloorTicks: Int = 1200,
                invincibilityRefreshBelowTicks: Int = 1200,
                invincibilityExtendTicks: Int = 0,
                baseShieldExtendTicks: Int = 600,
                baseShieldFloorTicks: Int = 1200,
                freezeTicks: Int = 480) {
        self.pickupLifetimeTicks = pickupLifetimeTicks
        self.pickupBlinkTicks = pickupBlinkTicks
        self.revealGraceTicks = revealGraceTicks
        self.armorUpAmount = armorUpAmount
        self.invincibilityFloorTicks = invincibilityFloorTicks
        self.invincibilityRefreshBelowTicks = invincibilityRefreshBelowTicks
        self.invincibilityExtendTicks = invincibilityExtendTicks
        self.baseShieldExtendTicks = baseShieldExtendTicks
        self.baseShieldFloorTicks = baseShieldFloorTicks
        self.freezeTicks = freezeTicks
    }

    public static let maxTimerTicks = 216_000
    public static let maxDamage = 99

    public func validationIssues() -> [String] {
        var issues: [String] = []
        func timer(_ value: Int, _ name: String, allowZero: Bool = false) {
            if value < (allowZero ? 0 : 1) || value > Self.maxTimerTicks {
                issues.append("\(name) must be \(allowZero ? 0 : 1)…\(Self.maxTimerTicks)")
            }
        }
        timer(pickupLifetimeTicks, "pickup_lifetime_ticks")
        timer(pickupBlinkTicks, "pickup_blink_ticks", allowZero: true)
        timer(revealGraceTicks, "reveal_grace_ticks", allowZero: true)
        if revealGraceTicks >= pickupLifetimeTicks { issues.append("reveal grace must end before the lifetime") }
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
        return issues
    }

    private static func saturatingAdd(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int.max : sum
    }

    public static let provisional = PickupRuleset()

    /// §10.1 id 13: a running timer is never shortened by a pickup.
    public func invincibilityTicks(afterPickupWith remaining: Int) -> Int {
        remaining <= invincibilityRefreshBelowTicks
            ? max(remaining, invincibilityFloorTicks)
            : Self.saturatingAdd(remaining, invincibilityExtendTicks)
    }

    /// §11.2: remaining = max(remaining + extend, floor).
    public func baseShieldTicks(afterPickupWith remaining: Int) -> Int {
        max(Self.saturatingAdd(remaining, baseShieldExtendTicks), baseShieldFloorTicks)
    }
}
