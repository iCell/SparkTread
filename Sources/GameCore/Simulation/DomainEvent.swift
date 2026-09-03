/// Ordered domain events (§13.8): stable IDs and primitive/value data only.
/// M1 emits the movement-relevant families; the enum grows per milestone.
/// Positions are NOT event data — presentation reads them from snapshots.
public enum DomainEvent: Codable, Equatable, Sendable {
    case playerActivated(playerID: PlayerID)
    case tankSpawned(entityID: Int, position: Vec2i, facing: Direction)
    case tankTurned(entityID: Int, facing: Direction)
    case weaponFired(entityID: Int, weaponID: String, channel: FireChannel, position: Vec2i)
    case dryFire(entityID: Int, weaponID: String)
    case projectileDestroyed(entityID: Int, position: Vec2i)
    case tankDamaged(entityID: Int, damage: Int, sourceWeaponID: String)
    case tankDestroyed(entityID: Int, position: Vec2i)
    case minePlaced(entityID: Int, level: Int, position: Vec2i)
    case mineTriggered(entityID: Int, position: Vec2i)
    case terrainChanged(cellX: Int, cellY: Int, quadrantMask: Int)
    case baseDamaged(damage: Int, remaining: Int)
    case baseShieldChanged(active: Bool)
    case explosion(position: Vec2i, radiusSubunits: Int)
    case playerEliminated(playerID: PlayerID)
    case pickupSpawned(entityID: Int, pickupID: String, position: Vec2i)
    case pickupCollected(entityID: Int, pickupID: String, byTank: Int)
    case equipmentChanged(entityID: Int, equipmentID: String)
    case enemyWaveStarted(archetypeID: String, position: Vec2i)
    case scoreChanged(delta: Int)
    case stageWon
    case stageLost(reason: String)
}
