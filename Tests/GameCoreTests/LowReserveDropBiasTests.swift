import Testing
@testable import GameCore

/// GAME_RULES R5.18 §10.2 (ADR-0027, owner 2026-10-09): with the reserves
/// at one or none, the extra life weighs six times in an enemy-death
/// drop's choice; above that the draw is exactly the table's own index,
/// so nothing moved for a player who is not in trouble.
@Suite struct LowReserveDropBiasTests {
    /// The stages' authored table (ADR-0025): 15 entries, one extra life.
    private let table = ["armor_up", "armor_up", "armor_up", "ammo_crate", "ammo_crate", "ammo_crate",
                         "speed_up", "speed_up", "power_up", "power_up",
                         "base_shield", "freeze_enemy", "bomb", "invincibility", "extra_life"]

    private func lifeShare(reserves: Int, draws: Int = 6000) -> Double {
        var rng = SplitMix64(seed: 7)
        var lives = 0
        for _ in 0..<draws where Stage.drawDrop(from: table, reserves: reserves, rng: &rng) == "extra_life" { lives += 1 }
        return Double(lives) / Double(draws)
    }

    @Test func theLastReservesPullTheExtraLifeForward() {
        let one = lifeShare(reserves: 1), none = lifeShare(reserves: 0), two = lifeShare(reserves: 2)
        #expect(one > 0.26 && one < 0.34)   // 6 of 20
        #expect(none > 0.26 && none < 0.34)
        #expect(two > 0.045 && two < 0.09)  // 1 of 15, as before R5.18
    }

    @Test func aboveTheThresholdTheDrawIsTheTableIndex() {
        var biased = SplitMix64(seed: 3), plain = SplitMix64(seed: 3)
        for _ in 0..<200 {
            let expected = table[plain.next(upperBound: table.count)]
            #expect(Stage.drawDrop(from: table, reserves: 2, rng: &biased) == expected)
        }
    }

    @Test func aTableWithoutALifeIsUnchangedAtLowReserves() {
        let noLife = table.filter { $0 != "extra_life" }
        var biased = SplitMix64(seed: 5), plain = SplitMix64(seed: 5)
        for _ in 0..<50 {
            #expect(Stage.drawDrop(from: noLife, reserves: 0, rng: &biased) == noLife[plain.next(upperBound: noLife.count)])
        }
    }

    /// Through the world: a kill at one reserve still spends the roll and
    /// one choice draw (§10.2's draw budget is unchanged), and the drop is
    /// an entry of the table.
    @Test func aKillAtOneReserveSpendsOneRollAndOneChoice() {
        var world = R5.world {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 40 * R5.cell, y: 22 * R5.cell))
            $0.stage = StageState(spawnQueue: ["normal_a"], maxAliveEnemies: 1, enemyStartDelayTicks: 6000,
                                  spawnPointsCells: [Vec2i(x: 50, y: 1)], playerRespawnCell: Vec2i(x: 3, y: 3),
                                  dropTable: ["extra_life", "speed_up"], dropChancePercent: 100)
            $0.withPlayer(.one) { $0.lives = 1 }
        }
        let enemy = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "normal_a",
                                    positionSubunits: Vec2i(x: 30 * R5.cell, y: 5 * R5.cell), facing: .down)
        world.withTank(entityID: enemy) { $0.armor = 0; $0.spawnProtectionTicks = 0; $0.killedBy = KillAttribution(playerID: .one) }
        let before = world.rng.drops.draws
        R5.step(&world, R5.settle)
        #expect(world.pickups.count == 1 && ["extra_life", "speed_up"].contains(world.pickups[0].pickupID))
        #expect(world.rng.drops.draws - before == 3) // roll, choice, placement
    }
}
