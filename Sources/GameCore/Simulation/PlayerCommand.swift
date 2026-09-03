/// Versioned session request enum (ADR-0002).
public enum SessionRequest: String, Codable, Sendable {
    case none, confirm, `continue`, activation
}

/// The ONLY external input contract (ADR-0002). AI intents are internal-only
/// `TankIntent` values and are never ingested through this type. A tick with
/// no command for a player resolves to neutral input.
public struct PlayerCommand: Codable, Equatable, Sendable {
    public let playerID: PlayerID
    public let targetTick: Int
    public let moveDirection: Direction?
    public let normalFirePressed: Bool
    public let specialFirePressed: Bool
    public let sessionRequest: SessionRequest

    public init(playerID: PlayerID, targetTick: Int, moveDirection: Direction? = nil,
                normalFirePressed: Bool = false, specialFirePressed: Bool = false,
                sessionRequest: SessionRequest = .none) {
        self.playerID = playerID
        self.targetTick = targetTick
        self.moveDirection = moveDirection
        self.normalFirePressed = normalFirePressed
        self.specialFirePressed = specialFirePressed
        self.sessionRequest = sessionRequest
    }
}

/// Internal-only AI output (ADR-0002); same movement/fire fields, derived
/// deterministically inside the simulation, never transmitted or recorded.
public struct TankIntent: Equatable, Sendable {
    public let entityID: Int
    public let moveDirection: Direction?
    public let normalFirePressed: Bool
    public let specialFirePressed: Bool

    public init(entityID: Int, moveDirection: Direction?,
                normalFirePressed: Bool = false, specialFirePressed: Bool = false) {
        self.entityID = entityID
        self.moveDirection = moveDirection
        self.normalFirePressed = normalFirePressed
        self.specialFirePressed = specialFirePressed
    }
}
