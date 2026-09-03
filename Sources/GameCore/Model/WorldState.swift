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
    public var rng: RNGStreams
    public var nextEntityID: Int

    public init(terrain: TerrainGrid, seed: UInt64) {
        self.tick = 0
        self.terrain = terrain
        self.players = []
        self.tanks = []
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
}
