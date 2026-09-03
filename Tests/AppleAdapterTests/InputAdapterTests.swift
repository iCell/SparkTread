import Testing
import GameCore
import GameApplication
@testable import AppleAdapters

@MainActor
@Suite struct HeldDirectionStoreTests {
    @Test func mostRecentlyPressedDirectionWins() {
        let store = HeldDirectionStore()
        store.press(.right)
        store.press(.left) // opposite pressed together: most recent wins (§6.3)
        #expect(store.held == .left)
        store.release(.left)
        #expect(store.held == .right) // falls back to the still-held press
        store.release(.right)
        #expect(store.held == nil)
    }

    @Test func analogQuantizationUsesHysteresis() {
        let store = HeldDirectionStore()
        store.updateFromAnalog(dx: 40, dy: 0, deadZone: 12)
        #expect(store.held == .right)
        // Near-diagonal wiggle stays on the current direction — no flicker.
        store.updateFromAnalog(dx: 30, dy: 28, deadZone: 12)
        #expect(store.held == .right)
        store.updateFromAnalog(dx: 28, dy: 30, deadZone: 12)
        #expect(store.held == .right)
        // A clearly dominant new axis switches.
        store.updateFromAnalog(dx: 5, dy: 40, deadZone: 12)
        #expect(store.held == .down)
        // Inside the dead zone releases everything.
        store.updateFromAnalog(dx: 3, dy: 3, deadZone: 12)
        #expect(store.held == nil)
    }
}

/// M1 exit criterion: corridor turning passes touch, keyboard, and
/// controller input scripts. Each script drives the SAME corridor fixture
/// through the adapter-side input path (physical events → HeldDirectionStore
/// → PlayerCommand); all three must turn and produce identical worlds.
@MainActor
@Suite struct CorridorInputScriptTests {
    /// Wall column at cell x=5, opening at rows 11–12 (as in the core tests).
    private func makeCorridorWorld() -> WorldState {
        var terrain = TerrainGrid(arena: .universal)
        let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
        for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
        for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
        for y in 1...25 where !(11...12).contains(y) { terrain[5, y] = TerrainCell(kind: .brick) }
        var world = WorldState(terrain: terrain, seed: 7)
        world.addPlayer(PlayerState(playerID: .one))
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3072, y: 3072), facing: .down)
        return world
    }

    /// Drives one tick per input event using the store's current held value.
    private func run(applying script: (Int, HeldDirectionStore) -> Void, ticks: Int) -> WorldState {
        let store = HeldDirectionStore()
        var world = makeCorridorWorld()
        for tick in 0..<ticks {
            script(tick, store)
            Simulation.step(&world, commands: [PlayerCommand(
                playerID: .one, targetTick: world.tick, moveDirection: store.held)])
        }
        return world
    }

    private let totalTicks = 220 // 160 ticks down + press right and roll to the lane

    /// Keyboard: discrete press/release events (what GCKeyboard delivers).
    private func keyboardWorld() -> WorldState {
        run(applying: { tick, store in
            if tick == 0 { store.press(.down) }
            if tick == 160 { store.release(.down); store.press(.right) }
        }, ticks: totalTicks)
    }

    /// Touch: floating-stick analog vectors through hysteresis quantization.
    private func touchWorld() -> WorldState {
        run(applying: { tick, store in
            switch tick {
            case 0..<160: store.updateFromAnalog(dx: 4, dy: 38, deadZone: 12)
            default: store.updateFromAnalog(dx: 41, dy: 6, deadZone: 12)
            }
        }, ticks: totalTicks)
    }

    /// Controller: D-pad values through the same analog path (up-positive y
    /// flipped by the adapter, as PhysicalInputAdapter does).
    private func controllerWorld() -> WorldState {
        run(applying: { tick, store in
            let (x, y): (Float, Float) = tick < 160 ? (0, -1) : (1, 0)
            store.updateFromAnalog(dx: Double(x), dy: Double(-y), deadZone: 0.5)
        }, ticks: totalTicks)
    }

    @Test func keyboardScriptTurnsIntoTheCorridor() {
        let world = keyboardWorld()
        #expect(world.tanks[0].facing == .right)
        #expect(world.tanks[0].positionSubunits.y == 11264) // snapped onto the lane
        #expect(world.tanks[0].positionSubunits.x > 5 * 1024) // drove through the opening
    }

    @Test func touchScriptTurnsIntoTheCorridor() {
        let world = touchWorld()
        #expect(world.tanks[0].facing == .right)
        #expect(world.tanks[0].positionSubunits.y == 11264)
        #expect(world.tanks[0].positionSubunits.x > 5 * 1024)
    }

    @Test func controllerScriptTurnsIntoTheCorridor() {
        let world = controllerWorld()
        #expect(world.tanks[0].facing == .right)
        #expect(world.tanks[0].positionSubunits.y == 11264)
        #expect(world.tanks[0].positionSubunits.x > 5 * 1024)
    }

    /// Identical held-direction sequences from different physical sources
    /// must be indistinguishable to the simulation (ADR-0002).
    @Test func allThreeSourcesProduceIdenticalWorlds() {
        let keyboard = keyboardWorld()
        #expect(keyboard == touchWorld())
        #expect(keyboard == controllerWorld())
        #expect(keyboard.checksum() == controllerWorld().checksum())
    }
}
