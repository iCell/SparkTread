import GameCore

/// The free-play lab fixture (`MOVEMENT_LAB=1`): a fixed, deterministic
/// arena with one player tank, used by the movement/combat lab and by tests.
/// `MovementLabSession` below is the session workflow for EVERY world — this
/// fixture or an authored stage — feeding tick commands into the kernel.
public enum MovementLabFixture {
    public static let seed: UInt64 = 0x5041_524B_5452_4541 // stable lab seed

    /// Builds the lab world: steel border, brick corridor walls (2-cell
    /// corridors matching the 2×2-cell tank), a water pool and an ice patch
    /// (ice slide stays inert in M1), and the player tank on a spawn cell.
    public static func makeWorld() -> WorldState {
        let arena = ArenaSpecification.universal
        var terrain = TerrainGrid(arena: arena)

        for x in 0..<arena.cellsWide {
            terrain[x, 0] = TerrainCell(kind: .steel)
            terrain[x, arena.cellsHigh - 1] = TerrainCell(kind: .steel)
        }
        for y in 0..<arena.cellsHigh {
            terrain[0, y] = TerrainCell(kind: .steel)
            terrain[arena.cellsWide - 1, y] = TerrainCell(kind: .steel)
        }

        func brickColumn(x: Int, yRange: ClosedRange<Int>) {
            for y in yRange { terrain[x, y] = TerrainCell(kind: .brick); terrain[x + 1, y] = TerrainCell(kind: .brick) }
        }
        func brickRow(y: Int, xRange: ClosedRange<Int>) {
            for x in xRange { terrain[x, y] = TerrainCell(kind: .brick); terrain[x, y + 1] = TerrainCell(kind: .brick) }
        }
        // Corridor lattice: vertical spines with gaps, horizontal shelves,
        // laid out for the 56-cell width (ADR-0009).
        brickColumn(x: 9, yRange: 1...16)
        brickColumn(x: 19, yRange: 9...25)
        brickColumn(x: 29, yRange: 1...16)
        brickColumn(x: 45, yRange: 9...25)
        brickRow(y: 19, xRange: 33...42)
        brickRow(y: 5, xRange: 36...42)
        brickRow(y: 5, xRange: 49...53)

        for y in 9...12 { for x in 49...53 { terrain[x, y] = TerrainCell(kind: .water) } }
        for y in 21...24 { for x in 4...8 { terrain[x, y] = TerrainCell(kind: .ice) } }

        var world = WorldState(terrain: terrain, seed: seed)
        world.addPlayer(PlayerState(playerID: .one))
        let cell = SpatialUnits.subunitsPerCell
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3 * cell, y: 3 * cell), facing: .down)

        // M2 combat targets: stationary enemy dummies and the base.
        for (archetype, x, y) in [("normal_a", 24, 8), ("normal_b", 34, 14), ("rapid_a", 13, 20)] {
            world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: archetype,
                            positionSubunits: Vec2i(x: x * cell, y: y * cell), facing: .down)
        }
        world.withTanksInEntityOrder { $0.spawnProtectionTicks = 0 }
        world.base = BaseState(teamID: 1, topLeftSubunits: Vec2i(x: 27 * cell, y: 23 * cell))
        return world
    }
}

/// Session workflow: owns the world, ingests at most one command per player
/// per tick, records the command log for replay, and tracks the periodic
/// checksum cadence (every `checksumInterval` ticks).
public struct MovementLabSession: Sendable {
    public private(set) var world: WorldState
    public private(set) var recording: ReplayRecording
    public let ruleset: MovementRuleset
    public let weapons: WeaponRuleset
    public let pickups: PickupRuleset
    /// Campaign header for the recording (ADR-0013): the stage id and the
    /// session state the world was built from; nil for lab/ad-hoc worlds.
    public let stageID: String?
    public let sessionState: SessionState?
    public let difficultyID: String?
    public static let checksumInterval = 60
    /// Training Arena rules (lab only, outside the recorded command stream;
    /// `TrainingArenaFixture`): enemies respawn on death, the base and the
    /// player's lives are topped up. Never set for authored stages.
    public private(set) var isTrainingArena = false
    /// What the panel asked for per enemy, so a respawn brings back the
    /// same tank (archetype tier, power level, equipment).
    public struct TrainingEnemy: Equatable, Sendable {
        public var archetype: String
        public var powerLevel: Int?
        public var equipmentID: String??
        public init(archetype: String, powerLevel: Int? = nil, equipmentID: String?? = nil) {
            self.archetype = archetype
            self.powerLevel = powerLevel
            self.equipmentID = equipmentID
        }
    }
    private var trainingRoster: [Int: TrainingEnemy] = [:]
    private var trainingSpawnCursor = 0

    /// Configuration rejected at the session boundary.
    public enum ConfigurationError: Error, Equatable {
        case invalidRules([String])
    }

    /// Every issue the three rulesets report — the same checks the replay
    /// player applies to a decoded recording, so a session never runs a
    /// configuration a recording of it would be refused for.
    public static func configurationIssues(ruleset: MovementRuleset, weapons: WeaponRuleset,
                                           pickups: PickupRuleset) -> [String] {
        ruleset.validationIssues() + weapons.validationIssues() + pickups.validationIssues()
    }

    /// Admission for configurations that come from data: throws instead of
    /// trapping. The initializer below is the trusted-code path and
    /// preconditions the same checks.
    public static func make(world: WorldState = MovementLabFixture.makeWorld(),
                            ruleset: MovementRuleset = .provisional,
                            weapons: WeaponRuleset = .provisional,
                            pickups: PickupRuleset = .provisional,
                            stageID: String? = nil, sessionState: SessionState? = nil,
                            difficultyID: String? = nil) throws -> MovementLabSession {
        let issues = configurationIssues(ruleset: ruleset, weapons: weapons, pickups: pickups)
            + (sessionState?.validationIssues ?? [])
        guard issues.isEmpty else { throw ConfigurationError.invalidRules(issues) }
        return MovementLabSession(world: world, ruleset: ruleset, weapons: weapons, pickups: pickups,
                                  stageID: stageID, sessionState: sessionState, difficultyID: difficultyID)
    }

    /// Trusted-code initializer: ALL THREE rulesets are preconditioned
    /// (R15-04: the session never appears to validate only one of them);
    /// data-driven callers use `make(...)`.
    /// The Training Arena session (`MOVEMENT_LAB=1`, the title's 训练场).
    public static func trainingArena() -> MovementLabSession {
        var session = MovementLabSession(world: TrainingArenaFixture.makeWorld())
        session.isTrainingArena = true
        for tank in session.world.tanks where tank.ownerPlayerID == nil {
            session.trainingRoster[tank.entityID] = TrainingEnemy(archetype: tank.archetypeID)
        }
        return session
    }

    public init(world: WorldState = MovementLabFixture.makeWorld(),
                ruleset: MovementRuleset = .provisional,
                weapons: WeaponRuleset = .provisional,
                pickups: PickupRuleset = .provisional,
                stageID: String? = nil, sessionState: SessionState? = nil, difficultyID: String? = nil) {
        let issues = Self.configurationIssues(ruleset: ruleset, weapons: weapons, pickups: pickups)
            + (sessionState?.validationIssues ?? [])
        precondition(issues.isEmpty, "session configuration rejected: \(issues)")
        self.world = world
        self.ruleset = ruleset
        self.weapons = weapons
        self.pickups = pickups
        self.stageID = stageID
        self.sessionState = sessionState
        self.difficultyID = difficultyID
        self.recording = ReplayRecording(initialWorld: world, movement: ruleset,
                                         weapons: weapons, pickups: pickups,
                                         stageID: stageID, sessionState: sessionState, difficultyID: difficultyID)
    }

    /// Resumes a suspended session (ADR-0003 §3): the snapshot world with
    /// the recording made so far, which keeps growing from the world's
    /// tick — the resumed run replays as one recording.
    public init(resuming world: WorldState, recording: ReplayRecording) {
        precondition(SuspendedSessionCheck.issues(world: world, recording: recording).isEmpty,
                     "snapshot rejected: \(SuspendedSessionCheck.issues(world: world, recording: recording))")
        self.world = world
        self.ruleset = recording.movement
        self.weapons = recording.weapons
        self.pickups = recording.pickups
        self.stageID = recording.stageID
        self.sessionState = recording.sessionState
        self.difficultyID = recording.difficultyID
        self.recording = recording
    }

    /// Debug hooks mutate the world outside the recorded command stream, so
    /// the recording restarts from the mutated world: what was recorded
    /// before is no longer reproducible from the old start.
    private mutating func rebaseRecording() {
        recording = ReplayRecording(initialWorld: world, movement: ruleset,
                                    weapons: weapons, pickups: pickups,
                                    stageID: stageID, sessionState: sessionState, difficultyID: difficultyID)
    }

    /// Advances one tick with the local player's held direction and fire
    /// button states.
    @discardableResult
    public mutating func advance(holding direction: Direction?,
                                 normalFire: Bool = false,
                                 specialFire: Bool = false) -> [DomainEvent] {
        let command = PlayerCommand(playerID: .one, targetTick: world.tick,
                                    moveDirection: direction,
                                    normalFirePressed: normalFire,
                                    specialFirePressed: specialFire)
        return advance(commands: [command])
    }

    // MARK: - Combat Lab debug panel hooks (development fixture only)

    /// Weapon debug panel: switches the player's special weapon and tops up
    /// its ammunition. Switching never erases stored ammunition (§8.1).
    public mutating func debugSelectSpecialWeapon(_ weaponID: String) {
        guard let weapon = weapons.weapon(weaponID), weapon.fireChannel == .special else { return }
        if let tankID = world.player(.one)?.tankEntityID {
            world.withTank(entityID: tankID) { $0.specialWeaponID = weaponID }
        }
        world.withPlayer(.one) {
            let current = $0.specialAmmoByWeapon[weaponID, default: 0]
            $0.specialAmmoByWeapon[weaponID] = max(current, weapon.refillAmount)
        }
        rebaseRecording()
    }

    /// Weapon debug panel: adjusts the player tank's power level (0–3).
    public mutating func debugSetPowerLevel(_ level: Int) {
        guard let tankID = world.player(.one)?.tankEntityID else { return }
        world.withTank(entityID: tankID) { $0.powerLevel = max(0, min(3, level)) }
        rebaseRecording()
    }

    /// Training Arena: drops a pickup one cell ahead of the player (or the
    /// nearest free cell), so any equipment, weapon or effect can be tried.
    @discardableResult
    public mutating func debugSpawnPickup(_ pickupID: String) -> Bool {
        guard isTrainingArena, let tank = world.player(.one)?.tankEntityID.flatMap({ world.tank(entityID: $0) }) else { return false }
        let cell = SpatialUnits.subunitsPerCell, footprint = SpatialUnits.standardTankFootprintSubunits
        let ahead = Vec2i(x: tank.positionSubunits.x + footprint / 2, y: tank.positionSubunits.y + footprint / 2)
            + tank.facing.vector * (footprint / 2 + cell)
        var events: [DomainEvent] = []
        let spawned = world.spawnStagePickup(pickupID, nearCell: Vec2i(x: ahead.x / cell, y: ahead.y / cell),
                                             rules: pickups, events: &events)
        if spawned { rebaseRecording() }
        return spawned
    }

    /// Training Arena: adds one enemy of `archetype` at the next spawn cell
    /// (nearest free footprint); it joins the roster, so it comes back
    /// when destroyed. False when no cell within the scan is free.
    @discardableResult
    public mutating func debugSpawnEnemy(_ archetype: String) -> Bool {
        debugSpawnEnemy(TrainingEnemy(archetype: archetype))
    }

    /// Training Arena: adds one enemy of a family with a chosen power level
    /// and equipment (owner 2026-09-10: pick the family, then its 火力 and
    /// 装备); nil keeps the archetype's own value.
    @discardableResult
    public mutating func debugSpawnEnemy(family: String, powerLevel: Int?, equipmentID: String??) -> Bool {
        debugSpawnEnemy(TrainingEnemy(archetype: "\(family)_a", powerLevel: powerLevel, equipmentID: equipmentID))
    }

    @discardableResult
    private mutating func debugSpawnEnemy(_ enemy: TrainingEnemy) -> Bool {
        guard isTrainingArena, TrainingArenaFixture.enemyArchetypes.contains(enemy.archetype) else { return false }
        if let power = enemy.powerLevel, !(0...3).contains(power) { return false }
        if case .some(.some(let equipment)) = enemy.equipmentID, !TrainingArenaFixture.equipmentIDs.contains(equipment) { return false }
        let origin = TrainingArenaFixture.enemySpawnCells[trainingSpawnCursor % TrainingArenaFixture.enemySpawnCells.count]
        trainingSpawnCursor += 1
        guard let cellPos = TrainingArenaFixture.freeCell(in: world, near: origin) else { return false }
        let id = TrainingArenaFixture.spawnEnemy(&world, archetype: enemy.archetype, at: cellPos)
        world.withTank(entityID: id) {
            if let power = enemy.powerLevel { $0.powerLevel = power }
            if let equipment = enemy.equipmentID { $0.equipmentID = equipment }
        }
        trainingRoster[id] = enemy
        rebaseRecording()
        return true
    }

    /// Training Arena: removes every enemy (and its respawn debt).
    public mutating func debugClearEnemies() {
        guard isTrainingArena else { return }
        let enemies = world.tanks.filter { $0.ownerPlayerID == nil }.map(\.entityID)
        for id in enemies { world.removeTankForTraining(entityID: id) }
        trainingRoster.removeAll()
        rebaseRecording()
    }

    /// Training Arena test hook: destroys a tank outright (the next tick
    /// runs its death and the respawn rule).
    public mutating func debugDestroyTank(_ entityID: Int) {
        guard isTrainingArena else { return }
        world.withTank(entityID: entityID) { $0.armor = 0; $0.shieldHP = 0 }
        rebaseRecording()
    }

    /// The arena's standing rules, applied after each tick: a destroyed
    /// enemy comes back at once (same archetype, next spawn cell, nearest
    /// free footprint), the base is repaired to full, the player's lives
    /// never run low. Each intervention rebases the recording (it is not
    /// part of the command stream).
    private mutating func applyTrainingArenaRules(events: inout [DomainEvent]) {
        var changed = false
        // The arena never ends: an objective that resolved (every enemy
        // cleared, or destroyed in one tick) is put back into play and its
        // outcome events are withheld from presentation.
        if let phase = world.stage?.phase, phase != .playing {
            world.stage?.phase = .playing
            events.removeAll {
                switch $0 {
                case .stageWon, .stageLost, .stageClearBonus: return true
                default: return false
                }
            }
            changed = true
        }
        for case .tankDestroyed(let id, nil, _) in events {
            guard let enemy = trainingRoster.removeValue(forKey: id) else { continue }
            let origin = TrainingArenaFixture.enemySpawnCells[trainingSpawnCursor % TrainingArenaFixture.enemySpawnCells.count]
            trainingSpawnCursor += 1
            guard let cellPos = TrainingArenaFixture.freeCell(in: world, near: origin) else {
                trainingRoster[id] = enemy // no room this tick: keep the debt, retry on the next death pass
                continue
            }
            let newID = TrainingArenaFixture.spawnEnemy(&world, archetype: enemy.archetype, at: cellPos)
            world.withTank(entityID: newID) {
                if let power = enemy.powerLevel { $0.powerLevel = power }
                if let equipment = enemy.equipmentID { $0.equipmentID = equipment }
            }
            trainingRoster[newID] = enemy
            changed = true
        }
        if var base = world.base, base.durability < base.maxDurability {
            base.durability = base.maxDurability
            world.base = base
            changed = true
        }
        if let lives = world.player(.one)?.lives, lives < TrainingArenaFixture.playerLives / 2 {
            world.withPlayer(.one) { $0.lives = TrainingArenaFixture.playerLives }
            changed = true
        }
        if changed { rebaseRecording() }
    }

    /// Lab convenience only: instantly respawns the player when no stage is
    /// active. Stage worlds use the real lives/respawn flow (§6.5).
    public mutating func debugRespawnPlayerIfNeeded() {
        guard world.stage == nil, world.player(.one)?.tankEntityID == nil else { return }
        let cell = SpatialUnits.subunitsPerCell
        world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                        positionSubunits: Vec2i(x: 3 * cell, y: 3 * cell), facing: .down)
        rebaseRecording()
    }

    @discardableResult
    public mutating func advance(commands: [PlayerCommand]) -> [DomainEvent] {
        recording.append(commands: commands, atTick: world.tick)
        var events = Simulation.step(&world, commands: commands, ruleset: ruleset,
                                     weapons: weapons, pickups: pickups)
        if world.tick % Self.checksumInterval == 0 {
            recording.appendChecksum(tick: world.tick, checksum: world.checksum())
            assert(WorldInvariants.violations(in: world).isEmpty,
                   "invariants violated: \(WorldInvariants.violations(in: world))")
        }
        if isTrainingArena { applyTrainingArenaRules(events: &events) }
        return events
    }
}

/// Consistency of a world with the recording that led to it (the checks a
/// resume needs before trusting a snapshot).
public enum SuspendedSessionCheck {
    public static func issues(world: WorldState, recording: ReplayRecording) -> [String] {
        var issues = MovementLabSession.configurationIssues(ruleset: recording.movement, weapons: recording.weapons,
                                                            pickups: recording.pickups)
        issues += WorldInvariants.violations(in: world)
        if recording.initialWorld.checksum() != recording.startChecksum { issues.append("recording start checksum mismatch") }
        if world.tick < recording.initialTick { issues.append("world precedes its recording") }
        if let last = recording.commandLog.last, last.tick >= world.tick { issues.append("commands beyond the snapshot") }
        return issues
    }
}
