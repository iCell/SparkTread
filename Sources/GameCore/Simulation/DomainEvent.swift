/// What a projectile met (§8.5 collision categories) — used by both the
/// surviving-contact and the destruction events.
public enum ImpactTarget: String, Codable, Sendable {
    case boundary, brick, steel, tank, base, mine, projectile, explosion, expired, deflected
}

/// Ordered domain events (§13.8): stable IDs and primitive/value data only.
/// Payloads carry what presentation needs to react without re-querying the
/// world — one drain can span several ticks, so the entity an event names
/// may already be gone (a collected pickup, a destroyed tank). Owner
/// identity, positions, facings, and impact kinds therefore travel with the
/// event; presentation never infers them from the current world.
///
/// Position anchors, per case (the presentation adapter converts each):
/// - tank events (`tankSpawned`, `weaponFired`, `tankDamaged`,
///   `tankShieldHit`, `tankDestroyed`): the tank's TOP-LEFT footprint
///   corner; `weaponFired.facing` orients muzzle effects;
/// - projectile events (`projectileHit`, `projectileDestroyed`): the
///   projectile box CENTER at the contact;
/// - `minePlaced`, `mineTriggered`, `mineRemoved`, `explosion`: the CENTER
///   of the mine hardware / blast;
/// - `pickupSpawned`, `pickupCollected`: the pickup's CELL CENTER;
/// - `enemyWaveStarted`: the spawn's tank TOP-LEFT;
/// - `terrainChanged`: the cell coordinates; `baseDamaged` carries no
///   position (the base is a singleton the scene already anchors).
public enum DomainEvent: Codable, Equatable, Sendable {
    case playerActivated(playerID: PlayerID)
    case tankSpawned(entityID: Int, ownerPlayerID: PlayerID?, position: Vec2i, facing: Direction)
    case tankTurned(entityID: Int, facing: Direction)
    case weaponFired(entityID: Int, ownerPlayerID: PlayerID?, weaponID: String,
                     channel: FireChannel, position: Vec2i, facing: Direction)
    case dryFire(entityID: Int, ownerPlayerID: PlayerID?, weaponID: String)
    /// A contact the projectile survived (penetration): it keeps flying.
    case projectileHit(entityID: Int, weaponID: String, position: Vec2i, impact: ImpactTarget)
    /// The end of a projectile, with what ended it.
    case projectileDestroyed(entityID: Int, weaponID: String, position: Vec2i, impact: ImpactTarget)
    case tankDamaged(entityID: Int, ownerPlayerID: PlayerID?, damage: Int,
                     sourceWeaponID: String, position: Vec2i)
    case tankShieldHit(entityID: Int, ownerPlayerID: PlayerID?, remaining: Int, position: Vec2i)
    case tankDestroyed(entityID: Int, ownerPlayerID: PlayerID?, position: Vec2i)
    case minePlaced(entityID: Int, ownerPlayerID: PlayerID?, level: Int, position: Vec2i)
    case mineTriggered(entityID: Int, position: Vec2i)
    /// A mine removed without detonating (disarmed by a shot, swept by
    /// Shield of Moon).
    case mineRemoved(entityID: Int, position: Vec2i)
    case terrainChanged(cellX: Int, cellY: Int, quadrantMask: Int)
    /// `allied` is true when the player's own fire hurt the base (ADR-0005
    /// requires a distinct own-fire cue).
    case baseDamaged(damage: Int, remaining: Int, allied: Bool)
    case baseShieldChanged(active: Bool)
    case explosion(position: Vec2i, radiusSubunits: Int)
    case playerEliminated(playerID: PlayerID)
    case pickupSpawned(entityID: Int, pickupID: String, position: Vec2i)
    case pickupCollected(entityID: Int, pickupID: String, byTank: Int, position: Vec2i)
    case equipmentChanged(entityID: Int, equipmentID: String)
    case enemyWaveStarted(archetypeID: String, position: Vec2i)
    case scoreChanged(delta: Int)
    case stageWon
    /// The won stage's clear bonuses (ADR-0012), already added to every
    /// active player's score on this tick; follows `stageWon`. Emitted only
    /// when the stage carries a bonus.
    case stageClearBonus(tally: Int, reward: Int)
    case stageLost(reason: String)
}
