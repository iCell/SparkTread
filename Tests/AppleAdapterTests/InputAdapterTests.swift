import Foundation
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

/// Source-token accounting (joint review PI-08 / R4-02 / R4-03): aliases,
/// devices and individual controls hold inputs independently; fire is
/// edge/hold per source; a disconnect touches one device only.
@MainActor
@Suite struct InputSourceAccountingTests {
    private let padA = "padA", padB = "padB"

    @Test func aliasesHoldTheSameDirectionIndependently() {
        let store = HeldDirectionStore()
        store.press(.up, from: .key("W"))
        store.press(.up, from: .key("Up"))
        store.release(.up, from: .key("Up"))
        #expect(store.held == .up) // W still held
        store.release(.up, from: .key("W"))
        #expect(store.held == nil)
    }

    @Test func keyRepeatDoesNotStealPriority() {
        let store = HeldDirectionStore()
        store.press(.up, from: .key("W"))
        store.press(.down, from: .key("S"))
        store.press(.up, from: .key("W")) // repeat of an already-held key
        #expect(store.held == .down)
        store.release(.up, from: .key("W"))
        store.press(.up, from: .key("W")) // a real re-press is a new press
        #expect(store.held == .up)
    }

    @Test func aNeutralDpadDoesNotEraseTheKeyboard() {
        let store = HeldDirectionStore()
        store.press(.left, from: .key("A"))
        store.updateFromAnalog(dx: 1, dy: 0, deadZone: 0.5, from: .controller(padA, control: "dpad"))
        #expect(store.held == .right) // most recent source wins
        store.updateFromAnalog(dx: 0, dy: 0, deadZone: 0.5, from: .controller(padA, control: "dpad"))
        #expect(store.held == .left) // keyboard input survives
    }

    @Test func normalFireIsOneEdgePerNewHolderAndSpecialIsHeldWhileAnyHolderRemains() {
        let store = HeldDirectionStore()
        store.pressNormalFire(from: .key("J"))
        store.pressNormalFire(from: .key("J")) // key repeat: no second edge
        #expect(store.consumeNormalFirePulse())
        #expect(!store.consumeNormalFirePulse())
        store.pressNormalFire(from: .key("U")) // a different key is a new press
        #expect(store.consumeNormalFirePulse())
        store.pressSpecialFire(from: .key("K"))
        store.pressSpecialFire(from: .controller(padA, control: "buttonB"))
        store.releaseSpecialFire(from: .key("K"))
        #expect(store.specialFireHeld) // controller still holds it
        store.releaseSpecialFire(from: .controller(padA, control: "buttonB"))
        #expect(!store.specialFireHeld)
    }

    /// R4-02: B and X on one gamepad are distinct controls.
    @Test func twoButtonsOnOneControllerAreDistinctHolders() {
        let store = HeldDirectionStore()
        let b = InputSource.controller(padA, control: "buttonB")
        let x = InputSource.controller(padA, control: "buttonX")
        #expect(b != x)
        PhysicalBindings.apply(.specialFire, pressed: true, from: b, to: store)
        PhysicalBindings.apply(.specialFire, pressed: true, from: x, to: store)
        PhysicalBindings.apply(.specialFire, pressed: false, from: b, to: store)
        #expect(store.specialFireHeld) // X is still physically down
        PhysicalBindings.apply(.specialFire, pressed: false, from: x, to: store)
        #expect(!store.specialFireHeld)
        #expect(PhysicalBindings.controllerButtons["buttonB"] == .specialFire)
        #expect(PhysicalBindings.controllerButtons["buttonX"] == .specialFire)
        #expect(PhysicalBindings.controllerButtons["buttonA"] == .normalFire)
        #expect(PhysicalBindings.keyboard["J"] == .normalFire && PhysicalBindings.keyboard["I"] == .specialFire)
    }

    /// R4-03: a disconnect releases only that device, including its own
    /// pending normal-fire pulse; the other controller keeps everything.
    @Test func disconnectReleasesOnlyThatDeviceIncludingItsPendingPulse() {
        let store = HeldDirectionStore()
        store.press(.down, from: .key("S"))
        store.pressSpecialFire(from: .controller(padB, control: "buttonB"))
        store.pressNormalFire(from: .controller(padB, control: "buttonA"))
        store.pressNormalFire(from: .controller(padA, control: "buttonA")) // a valid pulse from A
        store.updateFromAnalog(dx: 0, dy: 1, deadZone: 0.5, from: .controller(padB, control: "dpad"))
        let prefix = InputSource.controllerPrefix(padB)
        store.releaseAll { $0.id.hasPrefix(prefix) }
        #expect(store.held == .down)
        #expect(!store.specialFireHeld)
        #expect(store.consumeNormalFirePulse()) // pad A's pulse survives
        store.pressNormalFire(from: .controller(padB, control: "buttonA"))
        store.releaseAll { $0.id.hasPrefix(prefix) }
        #expect(!store.consumeNormalFirePulse()) // pad B's own pulse went with it
    }

    /// R4-03: a callback queued before its device disconnected is dropped
    /// at delivery, a later one from a connected device is applied.
    @Test func staleDeviceCallbackIsDroppedAtDelivery() async {
        let store = HeldDirectionStore()
        let generations = DeviceGenerations()
        PhysicalBindings.deliver(to: store, device: padA, generations: generations) {
            $0.pressSpecialFire(from: .controller(self.padA, control: "buttonB"))
        }
        generations.invalidate(padA) // disconnect races the queued delivery
        PhysicalBindings.deliver(to: store, device: padB, generations: generations) {
            $0.press(.left, from: .controller(self.padB, control: "dpad"))
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!store.specialFireHeld) // stale: dropped
        #expect(store.held == .left) // fresh: applied
    }

    @Test func releaseAllClearsFireAndMarksEarlierCallbacksStale() {
        let store = HeldDirectionStore()
        let before = ProcessInfo.processInfo.systemUptime
        store.pressSpecialFire(from: .touch)
        store.pressNormalFire(from: .touch)
        store.releaseAll()
        #expect(!store.specialFireHeld)
        #expect(!store.consumeNormalFirePulse())
        #expect(store.lastResetUptime >= before)
    }

    /// R4-04: while the application is inactive, presses are refused, not
    /// merely cleared once.
    @Test func inactiveStoreRefusesNewPresses() {
        let store = HeldDirectionStore()
        store.isAcceptingInput = false
        store.press(.up, from: .key("W"))
        store.pressSpecialFire(from: .touch)
        store.pressNormalFire(from: .touch)
        store.updateFromAnalog(dx: 1, dy: 0, deadZone: 0.5, from: .touch)
        #expect(store.held == nil && !store.specialFireHeld && !store.consumeNormalFirePulse())
        store.isAcceptingInput = true
        store.press(.up, from: .key("W"))
        #expect(store.held == .up)
    }
}
