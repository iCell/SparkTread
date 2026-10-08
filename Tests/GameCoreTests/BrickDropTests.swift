import Testing
@testable import GameCore

/// GAME_RULES R5.10 §10.5 (ADR-0023): a brick cell the player's round
/// empties can drop a pickup — by chance, under a stage cap, never for
/// enemy rounds, fort cells, hidden-pickup cells or extra lives, and
/// placed nearest the cleared cell.
@Suite struct BrickDropTests {
    /// A one-cell-thick brick wall ahead of the player's gun at x 10; two
    /// normal rounds empty cells (10, 3) and (10, 4) (§3.4).
    private func world(chance: Int = 1000, cap: Int = 2, table: [String] = ["speed_up"],
                       fort: [Vec2i] = [], hidden: [HiddenPickup] = []) -> WorldState {
        R5.world {
            R5.column(&$0, x: 10, .brick, ys: 2...5)
            // A base, or the stage is lost on its first tick (§11.4).
            $0.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 40 * R5.cell, y: 22 * R5.cell))
            // One enemy that never arrives: an empty queue would decide the
            // stage won on its first tick and freeze every shot (§11.4).
            $0.stage = StageState(spawnQueue: ["normal_a"], maxAliveEnemies: 1, enemyStartDelayTicks: 6000,
                                  spawnPointsCells: [Vec2i(x: 50, y: 1)], playerRespawnCell: Vec2i(x: 3, y: 3),
                                  dropTable: table, dropChancePercent: 0, hiddenPickups: hidden,
                                  fortTemplate: fort, brickDropChancePermille: chance, brickDropCap: cap)
        }
    }

    private func clearTwoCells(_ world: inout WorldState) {
        R5.step(&world, normal: true); R5.step(&world, R5.settle)
        R5.step(&world, normal: true); R5.step(&world, R5.settle)
        #expect(world.terrain[10, 3].kind == .ground && world.terrain[10, 4].kind == .ground)
    }

    @Test func aClearedCellDropsNearItselfAtFullChance() {
        var w = world(chance: 1000, cap: 1)
        clearTwoCells(&w)
        #expect(w.pickups.count == 1 && w.pickups.first?.pickupID == "speed_up")
        #expect(w.stage?.brickDropsGranted == 1 && w.stage?.clearedBrickCells.isEmpty == true)
        // Placed at the legal 2×2 area nearest the cleared cell (10, 3):
        // the cleared column itself is a one-cell slot, so the nearest
        // whole area sits beside it, within two cells.
        let at = w.pickups[0].cell
        #expect(abs(at.x - 10) <= 2 && abs(at.y - 3) <= 2, "placed at \(at)")
    }

    @Test func theCapStopsFurtherDropsAndRolls() {
        var w = world(chance: 1000, cap: 2)
        clearTwoCells(&w)          // two cells cleared in one tick → two drops
        #expect(w.pickups.count == 2 && w.stage?.brickDropsGranted == 2)
        let draws = w.rng.drops.draws
        R5.step(&w, normal: true); R5.step(&w, R5.settle)
        R5.step(&w, normal: true); R5.step(&w, R5.settle) // cells (10, 5) and more fall
        #expect(w.pickups.count == 2)
        #expect(w.rng.drops.draws == draws, "a capped stage rolls nothing")
    }

    @Test func zeroChanceDropsNothingButStillRolls() {
        var w = world(chance: 0)
        clearTwoCells(&w)
        #expect(w.pickups.isEmpty && w.stage?.brickDropsGranted == 0)
        #expect(w.rng.drops.draws == 2, "one roll per cleared cell, no choice draw")
    }

    @Test func anEnemyRoundClearsWithoutDropping() {
        var w = world(chance: 1000)
        // Two enemy shells from the right of the wall, the same two cells.
        for _ in 0..<2 {
            R5.shell(&w, "normal", team: 2, center: Vec2i(x: 14 * R5.cell, y: 4 * R5.cell), direction: .left)
            R5.step(&w, R5.settle)
        }
        #expect(w.terrain[10, 3].kind == .ground || w.terrain[10, 4].kind == .ground)
        #expect(w.pickups.isEmpty && w.stage?.brickDropsGranted == 0)
    }

    @Test func fortCellsAndHiddenPickupCellsNeverRoll() {
        var w = world(chance: 1000, fort: [Vec2i(x: 10, y: 3)],
                      hidden: [HiddenPickup(cell: Vec2i(x: 10, y: 4), pickupID: "shield", critical: false)])
        clearTwoCells(&w)
        // (10, 3) is fort; (10, 4) covers the hidden pickup's area.
        #expect(w.stage?.brickDropsGranted == 0)
        #expect(w.pickups.allSatisfy { $0.pickupID == "shield" }, "only the hidden pickup may appear")
    }

    @Test func anExtraLifeIsNeverABrickDrop() {
        var w = world(chance: 1000, table: ["extra_life"])
        clearTwoCells(&w)
        #expect(w.pickups.isEmpty && w.stage?.brickDropsGranted == 0)
        var mixed = world(chance: 1000, cap: 5, table: ["extra_life", "speed_up"])
        clearTwoCells(&mixed)
        #expect(!mixed.pickups.isEmpty && mixed.pickups.allSatisfy { $0.pickupID == "speed_up" })
    }

    /// The same seed and shots reproduce the same drops: the roll is on the
    /// `drop` stream and the placement spends no draw.
    @Test func brickDropsAreDeterministic() {
        var a = world(chance: 500), b = world(chance: 500)
        for _ in 0..<4 { R5.step(&a, normal: true); R5.step(&a, R5.settle); R5.step(&b, normal: true); R5.step(&b, R5.settle) }
        #expect(a.checksum() == b.checksum())
        #expect(a.pickups.map(\.cell) == b.pickups.map(\.cell))
    }
}
