/// What a projectile met (GAME_RULES §6) — carried by the destruction event.
public enum ImpactTarget: String, Codable, Sendable {
    case boundary, brick, steel, tank, base, projectile, expired
    /// A protected tank (spawn protection / invincibility): the shell ends
    /// without damage.
    case deflected
}

/// Ordered domain events: stable IDs and primitive/value data only. Payloads
/// carry what presentation needs without re-querying the world.
///
/// Position anchors, per case:
/// - tank events (`tankSpawned`, `weaponFired`, `tankDamaged`,
///   `tankShieldHit`, `tankDestroyed`): the tank's TOP-LEFT footprint
///   corner; `weaponFired.facing` orients muzzle effects;
/// - `projectileDestroyed`: the projectile box CENTER at the contact;
/// - `explosion`: the blast CENTER;
/// - `pickupSpawned`, `pickupCollected`: the pickup's 2×2 area CENTER;
/// - `enemyWaveStarted`: the spawn's tank TOP-LEFT;
/// - `terrainChanged`, `fireStarted`: cell coordinates.
public enum DomainEvent: Codable, Equatable, Sendable {
    case playerActivated(playerID: PlayerID)
    case tankSpawned(entityID: Int, ownerPlayerID: PlayerID?, position: Vec2i, facing: Direction)
    case tankTurned(entityID: Int, facing: Direction)
    case weaponFired(entityID: Int, ownerPlayerID: PlayerID?, weaponID: String,
                     channel: FireChannel, position: Vec2i, facing: Direction)
    case dryFire(entityID: Int, ownerPlayerID: PlayerID?, weaponID: String)
    /// The end of a projectile, with what ended it.
    case projectileDestroyed(entityID: Int, weaponID: String, position: Vec2i, impact: ImpactTarget)
    case tankDamaged(entityID: Int, ownerPlayerID: PlayerID?, damage: Int,
                     sourceWeaponID: String, position: Vec2i)
    case tankShieldHit(entityID: Int, ownerPlayerID: PlayerID?, remaining: Int, position: Vec2i)
    case tankDestroyed(entityID: Int, ownerPlayerID: PlayerID?, position: Vec2i)
    case terrainChanged(cellX: Int, cellY: Int, quadrantMask: Int)
    /// `allied` is true when the player's own fire hurt the base.
    case baseDamaged(damage: Int, remaining: Int, allied: Bool)
    case baseShieldChanged(active: Bool)
    case explosion(position: Vec2i, radiusSubunits: Int)
    /// A ground-fire patch was created on a cell (refreshes emit nothing).
    case fireStarted(cellX: Int, cellY: Int, color: FireColor)
    case playerEliminated(playerID: PlayerID)
    case pickupSpawned(entityID: Int, pickupID: String, position: Vec2i)
    case pickupCollected(entityID: Int, pickupID: String, byTank: Int, position: Vec2i)
    case equipmentChanged(entityID: Int, equipmentID: String)
    case enemyWaveStarted(archetypeID: String, position: Vec2i)
    case scoreChanged(delta: Int)
    /// An authored director phase fired (ADR-0015).
    case directorPhaseStarted(id: String, reinforcements: Int)
    case baseRepaired(restored: Int)
    case stageWon
    /// The won stage's clear bonuses (ADR-0012); follows `stageWon`.
    case stageClearBonus(tally: Int, reward: Int)
    case stageLost(reason: String)
}
