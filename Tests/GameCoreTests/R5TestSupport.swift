import Testing
@testable import GameCore

/// Shared fixtures for the GAME_RULES R5 suites. Geometry: 1 cell = 1024,
/// quadrant 512, tank 2048, shell half-extent 96. The player (team 1) sits
/// at cell (3, 3) facing right: centre (4096, 4096), muzzle x = 5120.
enum R5 {
    static let cell = SpatialUnits.subunitsPerCell
    /// Ticks after a shot within which any shell has crossed ten cells at the
    /// current rule speeds (the slowest, AP from rest, needs about 120).
    static let settle = 150

    static func world(seed: UInt64 = 5, _ build: (inout WorldState) -> Void = { _ in }) -> WorldState {
        var terrain = TerrainGrid(arena: .universal)
        let w = terrain.arena.cellsWide, h = terrain.arena.cellsHigh
        for x in 0..<w { terrain[x, 0] = TerrainCell(kind: .steel); terrain[x, h - 1] = TerrainCell(kind: .steel) }
        for y in 0..<h { terrain[0, y] = TerrainCell(kind: .steel); terrain[w - 1, y] = TerrainCell(kind: .steel) }
        var world = WorldState(terrain: terrain, seed: seed)
        world.addPlayer(PlayerState(playerID: .one))
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3 * cell, y: 3 * cell), facing: .right)
        world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
        build(&world)
        return world
    }

    /// Steps `n` ticks. `normal` is a PRESS (edge) on the first tick only;
    /// `special` is HELD for every tick.
    @discardableResult
    static func step(_ world: inout WorldState, _ n: Int = 1, direction: Direction? = nil,
                     normal: Bool = false, special: Bool = false,
                     weapons: WeaponRuleset = .provisional, pickups: PickupRuleset = .provisional) -> [DomainEvent] {
        var events: [DomainEvent] = []
        for i in 0..<n {
            events += Simulation.step(&world, commands: [PlayerCommand(
                playerID: .one, targetTick: world.tick, moveDirection: direction,
                normalFirePressed: normal && i == 0, specialFirePressed: special)],
                weapons: weapons, pickups: pickups)
        }
        return events
    }

    static func player(_ world: WorldState) -> TankState? {
        world.player(.one)?.tankEntityID.flatMap { world.tank(entityID: $0) }
    }

    @discardableResult
    static func enemy(_ world: inout WorldState, cellX: Int, cellY: Int, archetype: String = "normal_a",
                      facing: Direction = .left, armor: Int? = nil, shield: Int = 0) -> Int {
        let id = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: archetype,
                                 positionSubunits: Vec2i(x: cellX * cell, y: cellY * cell), facing: facing)
        let attributes = EnemyArchetypes.attributes(for: archetype)
        world.withTank(entityID: id) {
            $0.spawnProtectionTicks = 0
            $0.armor = armor ?? attributes.armor
            $0.maxArmor = max($0.armor, 8)
            $0.shieldHP = shield
            $0.specialWeaponID = Stage.enemyFamily(archetype)
        }
        return id
    }

    static func give(_ world: inout WorldState, _ weaponID: String, ammo: Int = 50, power: Int = 0) {
        if let id = world.player(.one)?.tankEntityID {
            world.withTank(entityID: id) { $0.specialWeaponID = weaponID; $0.powerLevel = power }
        }
        world.withPlayer(.one) { $0.specialAmmoByWeapon[weaponID] = ammo }
    }

    /// Injects a shell in flight (spawned before this tick).
    @discardableResult
    static func shell(_ world: inout WorldState, _ weaponID: String, team: Int, power: Int = 0,
                      center: Vec2i, direction: Direction, ownerPlayer: PlayerID? = nil) -> Int {
        let weapon = WeaponRuleset.provisional.weapon(weaponID)!
        let owner = world.claimEntityID()
        let id = world.claimEntityID()
        world.projectiles.append(ProjectileState(
            entityID: id, weaponID: weaponID, ownerEntityID: owner, ownerPlayerID: ownerPlayer,
            teamID: team, powerLevel: power, positionSubunits: center, direction: direction,
            velocity60: 60 * weapon.initialSpeedMilliSubunitsPerSecond, lifetimeRemainingTicks: weapon.lifetimeTicks))
        return id
    }

    static func column(_ world: inout WorldState, x: Int, _ kind: TerrainKind, mask: Int = 0b1111, ys: ClosedRange<Int> = 1...25) {
        for y in ys { world.terrain[x, y] = TerrainCell(kind: kind, quadrantMask: mask) }
    }

    static func fired(_ events: [DomainEvent], by entityID: Int? = nil, weapon: String? = nil) -> Int {
        events.filter {
            guard case .weaponFired(let id, _, let w, _, _, _) = $0 else { return false }
            return (entityID == nil || id == entityID) && (weapon == nil || w == weapon)
        }.count
    }

    static func destroyed(_ events: [DomainEvent], impact: ImpactTarget) -> Int {
        events.filter {
            guard case .projectileDestroyed(_, _, _, let i) = $0 else { return false }
            return i == impact
        }.count
    }
}
