import Foundation
import Testing
@testable import GameCore

/// Vertical-slice stress fixture (§17.1): 30 tanks, 200 active projectiles,
/// 100 mines, and heavy terrain damage. Asserts validity and determinism,
/// and reports headless throughput (the ≥10×-real-time release-device gate
/// runs on hardware; this debug-build bound is a coarse regression tripwire).
@Suite struct StressFixtureTests {
    private func makeStressWorld() -> WorldState {
        var terrain = TerrainGrid(arena: .universal)
        let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
        for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
        for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
        // Dense destructible field.
        for y in stride(from: 3, to: 24, by: 3) {
            for x in stride(from: 4, to: 52, by: 4) {
                terrain[x, y] = TerrainCell(kind: .brick)
            }
        }
        var world = WorldState(terrain: terrain, seed: 42)
        world.addPlayer(PlayerState(playerID: .one))

        // 30 tanks in a grid, alternating teams.
        var placed = 0
        outer: for row in 0..<5 {
            for column in 0..<6 {
                let id = world.spawnTank(
                    teamID: placed % 2 == 0 ? 1 : 2,
                    ownerPlayerID: placed == 0 ? .one : nil,
                    archetypeID: placed % 2 == 0 ? "player" : "normal_a",
                    positionSubunits: Vec2i(x: (2 + column * 9) * 1024, y: (2 + row * 5) * 1024),
                    facing: Direction(rawValue: placed % 4)!)
                world.withTank(entityID: id) { $0.spawnProtectionTicks = 0; $0.armor = 999; $0.maxArmor = 999 }
                placed += 1
                if placed == 30 { break outer }
            }
        }

        // 200 projectiles criss-crossing, mixed weapons.
        let weaponIDs = ["normal", "rapid", "ap", "explosion"]
        for i in 0..<200 {
            let weaponID = weaponIDs[i % 4]
            let weapon = WeaponRuleset.provisional.weapon(weaponID)!
            let id = world.claimEntityID()
            world.projectiles.append(ProjectileState(
                entityID: id, weaponID: weaponID, ownerEntityID: -1, ownerPlayerID: nil,
                teamID: i % 2 == 0 ? 1 : 2, powerLevel: i % 4,
                positionSubunits: Vec2i(x: (3 + (i * 7) % 50) * 1024 + 300,
                                        y: (2 + (i * 5) % 23) * 1024 + 300),
                direction: Direction(rawValue: i % 4)!,
                speedSubunitsPerTick: weapon.level(weapon.initialSpeedSubunitsPerTick, i % 4),
                lifetimeRemainingTicks: 600,
                penetrationRemaining: weapon.level(weapon.penetrationCount, i % 4),
                durability: weapon.level(weapon.projectileDurability, i % 4)))
        }

        // 100 armed mines.
        for i in 0..<100 {
            let id = world.claimEntityID()
            world.mines.append(MineState(
                entityID: id, level: i % 4, ownerEntityID: -1, ownerPlayerID: nil,
                teamID: i % 2 == 0 ? 2 : 1,
                positionSubunits: Vec2i(x: (2 + (i * 11) % 52) * 1024 + 512,
                                        y: (2 + (i * 13) % 23) * 1024 + 512),
                phase: .armed, phaseTicksRemaining: 0,
                triggerRadiusSubunits: 400, onWater: false))
        }
        return world
    }

    private func run(_ world: inout WorldState, ticks: Int) {
        for _ in 0..<ticks {
            Simulation.step(&world, commands: [PlayerCommand(
                playerID: .one, targetTick: world.tick,
                moveDirection: Direction(rawValue: (world.tick / 30) % 4),
                normalFirePressed: world.tick % 9 == 0)])
        }
    }

    @Test func stressFixtureStaysValidAndDeterministic() {
        var a = makeStressWorld(), b = makeStressWorld()
        let start = Date()
        run(&a, ticks: 600) // 10 simulated seconds of dense combat
        let elapsed = Date().timeIntervalSince(start)
        run(&b, ticks: 600)
        #expect(a.checksum() == b.checksum())
        let violations = WorldInvariants.violations(in: a)
        #expect(violations.isEmpty, "\(violations)")
        // Coarse debug-build tripwire: 10 simulated seconds within 20 s.
        #expect(elapsed < 20, "stress fixture too slow: \(elapsed)s for 600 ticks")
        print("stress fixture: 600 ticks in \(String(format: "%.2f", elapsed))s " +
              "(\(String(format: "%.1f", 10 / elapsed))× real time, debug build)")
    }
}
