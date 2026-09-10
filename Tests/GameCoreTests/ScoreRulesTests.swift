import Foundation
import Testing
@testable import GameCore

/// ADR-0012: the reference's stage-clear bonuses (tally bonus + reward) are
/// stage data paid on the deciding tick; reward categories drive the
/// results table.
private func makeWinnableWorld(bonus: ScoreRules.ClearBonus, score: Int = 0,
                               enemies: [String] = []) -> WorldState {
    var terrain = TerrainGrid(arena: .universal)
    let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
    for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
    for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
    var world = WorldState(terrain: terrain, seed: 5)
    var player = PlayerState(playerID: .one)
    player.score = score
    world.addPlayer(player)
    world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                    positionSubunits: Vec2i(x: 20 * 1024, y: 20 * 1024), facing: .up)
    world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 40 * 1024, y: 22 * 1024))
    world.stage = StageState(
        spawnQueue: enemies, maxAliveEnemies: 2, enemyStartDelayTicks: 600,
        spawnPointsCells: [Vec2i(x: 4, y: 1)], playerRespawnCell: Vec2i(x: 20, y: 20),
        dropTable: [], clearBonus: bonus)
    return world
}

private func stepOnce(_ world: inout WorldState) -> [DomainEvent] {
    Simulation.step(&world, commands: [PlayerCommand(playerID: .one, targetTick: world.tick)])
}

@Suite struct ScoreRulesTests {
    @Test func referenceTiersByStageNumber() {
        let rules = ScoreRules.reference
        #expect(rules.clearBonus(stageNumber: 0) == .none)
        #expect(rules.clearBonus(stageNumber: -3) == .none)
        for stage in [1, 5, 10] { #expect(rules.clearBonus(stageNumber: stage) == .init(tally: 200, reward: 330)) }
        for stage in [11, 18, 25] { #expect(rules.clearBonus(stageNumber: stage) == .init(tally: 600, reward: 660)) }
        for stage in [26, 32, 999] { #expect(rules.clearBonus(stageNumber: stage) == .init(tally: 1000, reward: 1000)) }
        #expect(ScoreRules(clearTiers: []).clearBonus(stageNumber: 7) == .none)
    }

    @Test func tiersAreOrderedOnInit() {
        let rules = ScoreRules(clearTiers: [
            .init(firstStage: 5, bonus: .init(tally: 50, reward: 5)),
            .init(firstStage: 1, bonus: .init(tally: 10, reward: 1)),
        ])
        #expect(rules.clearTiers.map(\.firstStage) == [1, 5])
        #expect(rules.clearBonus(stageNumber: 4).tally == 10 && rules.clearBonus(stageNumber: 5).tally == 50)
    }

    @Test func rewardCategoriesFollowTheSpecTableAndTheRowMultiplier() {
        let expected: [String: Int] = [
            "normal_a": 0, "normal_b": 0, "normal_c": 1, "normal_d": 1,
            "rapid_a": 2, "rapid_d": 2, "mine_a": 3, "mine_d": 3,
            "explosion_a": 4, "explosion_d": 4, "fire_a": 5, "fire_d": 5,
            "ap_a": 6, "ap_b": 6, "ap_c": 7, "ap_d": 7,
        ]
        for (id, category) in expected {
            #expect(EnemyArchetypes.attributes(for: id).rewardCategory == category, "\(id)")
        }
        #expect(EnemyArchetypes.attributes(for: "light").rewardCategory == 0) // unknown ids: the fodder row
        #expect((0..<8).map { ScoreRules.rewardMultiplier(category: $0) } == [1, 1, 2, 2, 3, 3, 4, 4])
    }

    @Test func aWonStagePaysBothBonusesOnTheDecidingTick() {
        var world = makeWinnableWorld(bonus: .init(tally: 200, reward: 330), score: 15)
        let events = stepOnce(&world)
        #expect(world.stage?.phase == .won)
        #expect(world.player(.one)?.score == 545)
        let wonIndex = events.firstIndex { if case .stageWon = $0 { true } else { false } }
        let bonusIndex = events.firstIndex { if case .stageClearBonus(200, 330) = $0 { true } else { false } }
        #expect(wonIndex != nil && bonusIndex != nil)
        if let wonIndex, let bonusIndex { #expect(bonusIndex == wonIndex + 1) }
        // Decided stages stay frozen: no second payment.
        _ = stepOnce(&world)
        #expect(world.player(.one)?.score == 545)
    }

    @Test func noBonusMeansNoPaymentAndNoEvent() {
        var world = makeWinnableWorld(bonus: .none, score: 15)
        let events = stepOnce(&world)
        #expect(world.stage?.phase == .won && world.player(.one)?.score == 15)
        #expect(!events.contains { if case .stageClearBonus = $0 { true } else { false } })
    }

    @Test func aLostStagePaysNothing() {
        var world = makeWinnableWorld(bonus: .init(tally: 200, reward: 330), score: 15, enemies: ["normal_a"])
        world.base?.durability = 0
        let events = stepOnce(&world)
        #expect(world.stage?.phase == .lost && world.player(.one)?.score == 15)
        #expect(!events.contains { if case .stageClearBonus = $0 { true } else { false } })
    }

    @Test func theBonusIsAuthoritativeStateChecksummedAndBounded() {
        let a = makeWinnableWorld(bonus: .none, enemies: ["normal_a"])
        let b = makeWinnableWorld(bonus: .init(tally: 200, reward: 330), enemies: ["normal_a"])
        #expect(a.checksum() != b.checksum())
        #expect(WorldInvariants.violations(in: b).isEmpty)
        var bad = b
        bad.stage?.clearBonus = .init(tally: -1, reward: 330)
        #expect(WorldInvariants.violations(in: bad).contains { $0.contains("clear bonus") })
    }

    @Test func recordingsWithoutTheBonusKeyStillDecode() throws {
        let stage = makeWinnableWorld(bonus: .init(tally: 600, reward: 660), enemies: ["normal_a"]).stage!
        let data = try JSONEncoder().encode(stage)
        #expect(try JSONDecoder().decode(StageState.self, from: data) == stage)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "clearBonus")
        let legacy = try JSONDecoder().decode(StageState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.clearBonus == .none)
        var expected = stage
        expected.clearBonus = .none
        #expect(legacy == expected)
    }
}
