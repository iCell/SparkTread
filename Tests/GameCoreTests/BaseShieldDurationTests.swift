import Testing
@testable import GameCore

/// GAME_RULES R5.23 §11.2 (owner 2026-10-09: 把基地变成钢铁之墙的那个装备生效
/// 时间，在简单难度延长三倍，其余两个难度下面延长两倍): the Flag On Guard's
/// extension and floor scale with the stage's difficulty percent.
@Suite struct BaseShieldDurationTests {
    private let rules = PickupRuleset.provisional

    @Test func theRulebookDurationsScaleByThePercent() {
        #expect(rules.baseShieldTicks(afterPickupWith: 0) == 1200)                // 20 s, unchanged at 100
        #expect(rules.baseShieldTicks(afterPickupWith: 0, percent: 300) == 3600)  // casual: 60 s
        #expect(rules.baseShieldTicks(afterPickupWith: 0, percent: 200) == 2400)  // standard, veteran: 40 s
        // A second pickup extends by the scaled extension.
        #expect(rules.baseShieldTicks(afterPickupWith: 3000, percent: 300) == 4800)
        #expect(rules.baseShieldTicks(afterPickupWith: 2000, percent: 200) == 3200)
    }

    @Test func aPickupInAStageUsesItsPercent() {
        var world = R5.world {
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 40 * R5.cell, y: 22 * R5.cell))
            $0.stage = StageState(spawnQueue: ["normal_a"], maxAliveEnemies: 1, enemyStartDelayTicks: 6000,
                                  spawnPointsCells: [Vec2i(x: 50, y: 1)], playerRespawnCell: Vec2i(x: 3, y: 3),
                                  dropTable: [], dropChancePercent: 0, baseShieldDurationPercent: 300)
        }
        var events: [DomainEvent] = []
        // On the player's own cells, no grace: collected on the next tick.
        Stage.placePickup(&world, pickupID: "base_shield", cell: Vec2i(x: 3, y: 3), critical: false,
                          graceTicks: 0, rules: rules, events: &events)
        R5.step(&world)
        #expect(world.pickups.isEmpty)
        let remaining = world.base?.shieldRemainingTicks ?? 0
        #expect(remaining >= 3598 && remaining <= 3600) // 60 s, less the tick(s) it has run
    }
}
