/// Ordered domain events (§13.8): stable IDs and primitive/value data only.
/// M1 emits the movement-relevant families; the enum grows per milestone.
/// Positions are NOT event data — presentation reads them from snapshots.
public enum DomainEvent: Codable, Equatable, Sendable {
    case playerActivated(playerID: PlayerID)
    case tankSpawned(entityID: Int, position: Vec2i, facing: Direction)
    case tankTurned(entityID: Int, facing: Direction)
}
