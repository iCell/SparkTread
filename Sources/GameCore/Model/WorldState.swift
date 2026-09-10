/// The complete authoritative world: a value type, fully Codable, including
/// RNG stream positions and buffer/slide state (ADR-0003). Authoritative
/// state never lives in class graphs. Tanks are kept sorted ascending by
/// `entityID`; entity processing order is explicit (§14.3).
public struct WorldState: Codable, Equatable, Sendable {
    public var tick: Int
    public var terrain: TerrainGrid
    /// Sorted ascending by playerID; mutate through the accessors.
    public internal(set) var players: [PlayerState]
    /// Sorted ascending by entityID; mutate through the accessors.
    public internal(set) var tanks: [TankState]
    /// Combat entities, each sorted ascending by entityID (M2).
    public internal(set) var projectiles: [ProjectileState]
    public internal(set) var mines: [MineState]
    public internal(set) var fireHazards: [FireHazardState]
    public internal(set) var pickups: [PickupState]
    public internal(set) var spawnTelegraphs: [SpawnTelegraph]
    public var base: BaseState?
    public var stage: StageState?
    public var rng: RNGStreams
    public var nextEntityID: Int

    public init(terrain: TerrainGrid, seed: UInt64) {
        self.tick = 0
        self.terrain = terrain
        self.players = []
        self.tanks = []
        self.projectiles = []
        self.mines = []
        self.fireHazards = []
        self.pickups = []
        self.spawnTelegraphs = []
        self.base = nil
        self.stage = nil
        self.rng = RNGStreams(seed: seed)
        self.nextEntityID = 1
    }

    public var arena: ArenaSpecification { terrain.arena }

    // MARK: - Players

    public mutating func addPlayer(_ player: PlayerState) {
        precondition(playerIndex(player.playerID) == nil, "duplicate player")
        players.append(player)
        players.sort { $0.playerID < $1.playerID }
    }

    public func player(_ id: PlayerID) -> PlayerState? {
        playerIndex(id).map { players[$0] }
    }

    /// Training-arena hook: removes a tank outright (no death, no drop,
    /// no score); the owning player's tank link is cleared.
    public mutating func removeTankForTraining(entityID: Int) {
        guard let index = tanks.firstIndex(where: { $0.entityID == entityID }) else { return }
        let owner = tanks[index].ownerPlayerID
        tanks.remove(at: index)
        if let owner { withPlayer(owner) { if $0.tankEntityID == entityID { $0.tankEntityID = nil } } }
    }

    public mutating func withPlayer(_ id: PlayerID, _ body: (inout PlayerState) -> Void) {
        guard let i = playerIndex(id) else { return }
        body(&players[i])
    }

    private func playerIndex(_ id: PlayerID) -> Int? {
        players.firstIndex { $0.playerID == id }
    }

    // MARK: - Tanks

    @discardableResult
    public mutating func spawnTank(teamID: Int, ownerPlayerID: PlayerID?, archetypeID: String,
                                   positionSubunits: Vec2i, facing: Direction) -> Int {
        let id = nextEntityID
        nextEntityID += 1
        tanks.append(TankState(entityID: id, teamID: teamID, ownerPlayerID: ownerPlayerID,
                               archetypeID: archetypeID, positionSubunits: positionSubunits,
                               facing: facing))
        tanks.sort { $0.entityID < $1.entityID }
        if let ownerPlayerID {
            withPlayer(ownerPlayerID) { $0.tankEntityID = id }
        }
        return id
    }

    public func tank(entityID: Int) -> TankState? {
        tanks.first { $0.entityID == entityID }
    }

    public mutating func withTank(entityID: Int, _ body: (inout TankState) -> Void) {
        guard let i = tanks.firstIndex(where: { $0.entityID == entityID }) else { return }
        body(&tanks[i])
    }

    public mutating func withTanksInEntityOrder(_ body: (inout TankState) -> Void) {
        for i in tanks.indices { body(&tanks[i]) }
    }

    mutating func claimEntityID() -> Int {
        defer { nextEntityID += 1 }
        return nextEntityID
    }

    mutating func removeTank(entityID: Int) {
        tanks.removeAll { $0.entityID == entityID }
        for i in players.indices where players[i].tankEntityID == entityID {
            players[i].tankEntityID = nil
        }
    }
}
