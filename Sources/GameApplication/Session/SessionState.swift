import GameCore

/// The per-player state a campaign carries from one stage into the next
/// (plan §16.3 `initial_session_state`: carried upgrades, ammunition and
/// lives; ADR-0013): everything of `PlayerState` that outlives a stage.
/// Armor is stage data (§6.5 resets it on every spawn) and is not carried;
/// the tank itself is rebuilt by the next stage's builder. A won stage's
/// EXIT state is the value at its deciding tick, clear bonuses included
/// (ADR-0012); the next stage's INITIAL state must equal it (the campaign
/// replay harness checks exactly that).
public struct SessionState: Codable, Equatable, Sendable {
    public var lives: Int
    public var score: Int
    public var specialAmmoByWeapon: [String: Int]
    public var retainedSpeedLevel: Int
    public var retainedPowerLevel: Int
    public var retainedEquipmentID: String?
    public var retainedSpecialWeaponID: String

    public init(lives: Int, score: Int, specialAmmoByWeapon: [String: Int],
                retainedSpeedLevel: Int = 0, retainedPowerLevel: Int = 0,
                retainedEquipmentID: String? = nil, retainedSpecialWeaponID: String = "rapid") {
        self.lives = lives
        self.score = score
        self.specialAmmoByWeapon = specialAmmoByWeapon
        self.retainedSpeedLevel = retainedSpeedLevel
        self.retainedPowerLevel = retainedPowerLevel
        self.retainedEquipmentID = retainedEquipmentID
        self.retainedSpecialWeaponID = retainedSpecialWeaponID
    }

    /// Campaign start (plan §6.4 PROVISIONAL values): 3 lives, no score,
    /// Rapid with 50 rounds, no upgrades.
    public static let campaignStart: SessionState = {
        let fresh = PlayerState(playerID: .one)
        return SessionState(lives: fresh.lives, score: fresh.score,
                            specialAmmoByWeapon: fresh.specialAmmoByWeapon,
                            retainedSpeedLevel: fresh.retainedSpeedLevel,
                            retainedPowerLevel: fresh.retainedPowerLevel,
                            retainedEquipmentID: fresh.retainedEquipmentID,
                            retainedSpecialWeaponID: fresh.retainedSpecialWeaponID)
    }()

    /// The state a world's player carries out of a stage: the retained
    /// upgrades are read from the live tank when it exists (the retention
    /// fields are refreshed only on death), else from the retained fields.
    public static func carried(from world: WorldState, player id: PlayerID = .one) -> SessionState? {
        guard let player = world.player(id) else { return nil }
        let tank = player.tankEntityID.flatMap { world.tank(entityID: $0) }
        return SessionState(
            lives: max(0, player.lives), score: player.score,
            specialAmmoByWeapon: player.specialAmmoByWeapon,
            retainedSpeedLevel: tank?.speedLevel ?? player.retainedSpeedLevel,
            retainedPowerLevel: tank?.powerLevel ?? player.retainedPowerLevel,
            retainedEquipmentID: tank?.equipmentID ?? player.retainedEquipmentID,
            retainedSpecialWeaponID: tank?.specialWeaponID ?? player.retainedSpecialWeaponID)
    }

    /// Writes the carried values into a fresh stage player.
    public func apply(to player: inout PlayerState) {
        player.lives = lives
        player.score = score
        player.specialAmmoByWeapon = specialAmmoByWeapon
        player.retainedSpeedLevel = retainedSpeedLevel
        player.retainedPowerLevel = retainedPowerLevel
        player.retainedEquipmentID = retainedEquipmentID
        player.retainedSpecialWeaponID = retainedSpecialWeaponID
    }

    /// Domain checks mirroring `WorldInvariants` for the player fields, so
    /// a carried state from data (a save, a replay header) is refused
    /// before it builds a world.
    public var validationIssues: [String] {
        var issues: [String] = []
        if lives < 0 || lives > WorldInvariants.maxLives { issues.append("lives \(lives) out of domain") }
        if score < 0 || score > WorldInvariants.maxScore { issues.append("score out of domain") }
        for (weapon, ammo) in specialAmmoByWeapon.sorted(by: { $0.key < $1.key }) {
            if weapon.isEmpty { issues.append("empty weapon id in ammo") }
            if ammo < 0 || ammo > WorldInvariants.maxCount { issues.append("ammo for \(weapon) out of domain") }
        }
        if !(0...3).contains(retainedSpeedLevel) { issues.append("speed level \(retainedSpeedLevel) out of domain") }
        if !(0...3).contains(retainedPowerLevel) { issues.append("power level \(retainedPowerLevel) out of domain") }
        if retainedSpecialWeaponID.isEmpty { issues.append("empty special weapon id") }
        return issues
    }
}
