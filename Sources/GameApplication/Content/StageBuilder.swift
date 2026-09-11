import GameCore

/// Builds an authoritative `WorldState` from a `StageDefinition`.
/// Pure: construction order is fixed so entity IDs (and thus checksums) are
/// stable across loads. The definition is validated FIRST (R15-02): a
/// rejected definition never reaches the allocation of its spawn queue —
/// the validator's budget is what bounds that allocation.
public enum StageBuilder {
    public enum BuildError: Error, Equatable {
        case badTerrainKind(String), badSeed(String), invalidDefinition([String])
    }

    /// `session` is the state carried into this stage (ADR-0013): lives,
    /// score, ammunition and retained upgrades land on player one; the tank
    /// spawns with the stage's armor and the retained upgrades applied.
    public static func build(_ def: StageDefinition, rules: PickupRuleset = .provisional,
                             session: SessionState = .campaignStart,
                             difficulty: DifficultyDefinition = .standard) throws -> WorldState {
        let issues = StageValidator.validate(def) + session.validationIssues + DifficultyValidator.validate(difficulty)
        guard issues.isEmpty else { throw BuildError.invalidDefinition(issues) }
        let arena = ArenaSpecification.universal
        var terrain = TerrainGrid(arena: arena)

        let borderKind = try kind(def.terrain.border)
        for x in 0..<arena.cellsWide {
            terrain[x, 0] = TerrainCell(kind: borderKind)
            terrain[x, arena.cellsHigh - 1] = TerrainCell(kind: borderKind)
        }
        for y in 0..<arena.cellsHigh {
            terrain[0, y] = TerrainCell(kind: borderKind)
            terrain[arena.cellsWide - 1, y] = TerrainCell(kind: borderKind)
        }
        for layer in def.terrain.layers {
            let cellKind = try kind(layer.kind)
            for rect in layer.rects ?? [] {
                for cy in rect[1]...rect[3] {
                    for cx in rect[0]...rect[2] where terrain.isInside(cellX: cx, cellY: cy) {
                        terrain[cx, cy] = TerrainCell(kind: cellKind)
                    }
                }
            }
            for cell in layer.cells ?? [] where terrain.isInside(cellX: cell[0], cellY: cell[1]) {
                terrain[cell[0], cell[1]] = TerrainCell(kind: cellKind)
            }
        }

        guard let seed = UInt64(def.seed) else { throw BuildError.badSeed(def.seed) }
        var world = WorldState(terrain: terrain, seed: seed)
        var player = PlayerState(playerID: .one)
        session.apply(to: &player)
        world.addPlayer(player)

        let cell = SpatialUnits.subunitsPerCell
        // Player 1 only in V1 (§6.4); ignore any reserved player-2 spawn.
        let playerCell = def.playerSpawnsByID["1"] ?? [21, 24]
        let tankID = world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                                     positionSubunits: Vec2i(x: playerCell[0] * cell, y: playerCell[1] * cell),
                                     facing: .up)
        // Carried upgrades ride on the first tank of the stage (the same
        // retention a respawn applies, §6.5); armor is the stage's.
        world.withTank(entityID: tankID) {
            $0.speedLevel = session.retainedSpeedLevel
            $0.powerLevel = session.retainedPowerLevel
            $0.equipmentID = session.retainedEquipmentID
            $0.specialWeaponID = session.retainedSpecialWeaponID
        }
        world.base = BaseState(teamID: 1,
                               topLeftSubunits: Vec2i(x: def.baseSpawn[0] * cell,
                                                      y: def.baseSpawn[1] * cell))

        // Interleave the ordered composition into a deterministic queue,
        // then apply the difficulty's composition variant (ADR-0015).
        var pools = def.enemyComposition.map { ($0.archetype, $0.count) }
        var queue: [String] = []
        while pools.contains(where: { $0.1 > 0 }) {
            for i in pools.indices where pools[i].1 > 0 {
                queue.append(pools[i].0)
                pools[i].1 -= 1
            }
        }

        // Carrier assignments index into the interleaved queue.
        var carriedQueue: [String?] = []
        if let drops = def.carriedDrops, !drops.isEmpty {
            carriedQueue = Array(repeating: nil, count: queue.count)
            for drop in drops where drop.queueIndex >= 0 && drop.queueIndex < queue.count {
                carriedQueue[drop.queueIndex] = drop.pickup
            }
        }

        world.stage = StageState(
            spawnQueue: difficulty.apply(toComposition: queue),
            maxAliveEnemies: def.maxAliveEnemies,
            enemyStartDelayTicks: def.initialEnemyDelayTicks,
            spawnPointsCells: def.enemySpawns.map { Vec2i(x: $0[0], y: $0[1]) },
            telegraphTicks: difficulty.telegraphTicks(authored: def.telegraphTicks),
            playerRespawnCell: Vec2i(x: playerCell[0], y: playerCell[1]),
            dropTable: def.dropTable,
            dropChancePercent: def.dropChancePercent,
            carriedPickupQueue: carriedQueue,
            hiddenPickups: (def.hiddenPickups ?? []).map {
                HiddenPickup(cell: Vec2i(x: $0.cell[0], y: $0.cell[1]), pickupID: $0.id)
            },
            // Validated present above; the fallback is unreachable data hygiene.
            clearBonus: ScoreRules.reference.clearBonus(stageNumber: def.stageNumber ?? 1),
            enemyBehavior: difficulty.enemyBehavior,
            directorPhases: (def.directorPhases ?? []).map { phase in
                DirectorPhase(id: phase.id, afterSpawned: phase.afterSpawned,
                              reinforcements: difficulty.apply(toComposition: phase.reinforcements),
                              maxAliveEnemies: phase.maxAliveEnemies, repairsBase: phase.repairsBase)
            })

        var events: [DomainEvent] = []
        for pickup in def.pickupSpawns {
            world.spawnStagePickup(pickup.id, nearCell: Vec2i(x: pickup.cell[0], y: pickup.cell[1]),
                                   rules: rules, events: &events)
        }
        return world
    }

    private static func kind(_ name: String) throws -> TerrainKind {
        switch name {
        case "ground": .ground
        case "brick": .brick
        case "steel": .steel
        case "white_brick": .whiteBrick
        case "white_steel": .whiteSteel
        case "water": .water
        case "ice": .ice
        case "foliage": .foliage
        case "base": .base
        default: throw BuildError.badTerrainKind(name)
        }
    }
}
