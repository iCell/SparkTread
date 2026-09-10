import Foundation
import Testing
import GameCore
@testable import GameApplication

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let vs01URL = repoRoot
    .appendingPathComponent("Content/stages/frontier_01_first_defense.json")

/// PI-07: a recording is self-contained — initial world, all rulesets — so
/// an authored stage session at a nonzero tick replays through the public
/// encode/decode/replay API.
@Suite struct ReplayRecordingTests {
    private func combatScript(_ session: inout MovementLabSession, ticks: Int) {
        for i in 0..<ticks {
            let dir: Direction? = [Direction.up, .right, nil, .left, .down][(i / 45) % 5]
            session.advance(holding: dir, normalFire: i % 17 == 0, specialFire: i % 60 < 12)
        }
    }

    @Test func stageSessionAtANonZeroTickReplaysThroughEncodeDecode() throws {
        var world = try StageLoader.loadWorld(at: vs01URL)
        for _ in 0..<100 { Simulation.step(&world, commands: []) } // nonzero initial tick
        var casual = WeaponRuleset.provisional
        casual.alliedBaseDamage = false // non-default configuration must travel
        var session = MovementLabSession(world: world, weapons: casual)
        combatScript(&session, ticks: 420)
        #expect(session.recording.initialTick == 100)
        #expect(!session.recording.commandLog.isEmpty)
        #expect(session.recording.checksums.count == 7)

        let data = try JSONEncoder().encode(session.recording)
        let decoded = try JSONDecoder().decode(ReplayRecording.self, from: data)
        #expect(decoded == session.recording)
        let replayed = try ReplayPlayer.replay(decoded, ticks: 420)
        #expect(replayed == session.recording.checksums)
    }

    @Test func tamperedInitialWorldIsRejected() throws {
        let session = MovementLabSession()
        // A recording whose checksum no longer matches the world under it
        // is rejected before playback; so is an older format.
        let data = try JSONEncoder().encode(session.recording)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["startChecksum"] = 12345
        let corrupted = try JSONDecoder().decode(ReplayRecording.self,
                                                 from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: ReplayPlayer.ReplayError.self) { try ReplayPlayer.replay(corrupted, ticks: 10) }
        // An earlier format is refused at the DECODING boundary, before any
        // other field is read — the one contract for old files.
        json["formatVersion"] = 1
        #expect(throws: ReplayPlayer.ReplayError.unsupportedFormat(1)) {
            try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        }
        // A REAL format-2 file: its embedded pickup rules predate
        // `dropsSpawnAtRandomCells`, so field-by-field decoding would fail
        // with a key-not-found error about that field. The header-first
        // check reports the version boundary instead (R8-03 closeout).
        json["formatVersion"] = 2
        var oldPickups = try #require(json["pickups"] as? [String: Any])
        #expect(oldPickups.removeValue(forKey: "dropsSpawnAtRandomCells") != nil)
        json["pickups"] = oldPickups
        #expect(throws: ReplayPlayer.ReplayError.unsupportedFormat(2)) {
            try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        }
        // Format 3 (before the campaign header and the clear bonus) is
        // refused the same way.
        json["formatVersion"] = 3
        #expect(throws: ReplayPlayer.ReplayError.unsupportedFormat(3)) {
            try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        }
        // Format 4 (before difficulty profiles and director phases) too.
        json["formatVersion"] = 4
        #expect(throws: ReplayPlayer.ReplayError.unsupportedFormat(4)) {
            try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        }
        json["formatVersion"] = 5
        #expect(throws: ReplayPlayer.ReplayError.unsupportedFormat(5)) {
            try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        }
        json["formatVersion"] = 6
        #expect(throws: ReplayPlayer.ReplayError.unsupportedFormat(6)) {
            try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        }
        // The same old shape with a current version number is a plain
        // schema error — the format number is the boundary, not the shape.
        json["formatVersion"] = 7
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        }
        #expect(ReplayRecording.currentFormatVersion == 7)
    }

    @Test func debugMutationsRebaseTheRecording() {
        var session = MovementLabSession()
        combatScript(&session, ticks: 90)
        #expect(session.recording.initialTick == 0)
        session.debugSetPowerLevel(2) // outside the command stream
        #expect(session.recording.initialTick == 90)
        #expect(session.recording.commandLog.isEmpty)
        #expect(session.recording.initialWorld == session.world)
    }

    /// R4-05: a structurally decodable recording that is not runnable is a
    /// ReplayError, never a trap — malformed weapon arrays, invalid pickup
    /// rules, a negative initial tick, duplicate command envelopes, an
    /// overflowing tick range.
    @Test func malformedRecordingsAreRejectedNotTrapped() throws {
        var session = MovementLabSession()
        session.advance(holding: nil, normalFire: true)
        let data = try JSONEncoder().encode(session.recording)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        func decode(_ json: [String: Any]) throws -> ReplayRecording {
            try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        }
        // Weapon per-level array emptied in JSON.
        var weapons = try #require(json["weapons"] as? [String: Any])
        var list = try #require(weapons["weapons"] as? [[String: Any]])
        list[0]["cooldownTicks"] = []
        weapons["weapons"] = list
        var broken = json; broken["weapons"] = weapons
        #expect(throws: ReplayPlayer.ReplayError.self) { try ReplayPlayer.replay(try decode(broken), ticks: 1) }

        // Invalid pickup rules.
        var pickups = try #require(json["pickups"] as? [String: Any])
        pickups["freezeTicks"] = 0
        var badRules = json; badRules["pickups"] = pickups
        #expect(throws: ReplayPlayer.ReplayError.self) { try ReplayPlayer.replay(try decode(badRules), ticks: 1) }

        // Negative initial tick inside the embedded world.
        var world = try #require(json["initialWorld"] as? [String: Any])
        world["tick"] = -1
        var badWorld = json; badWorld["initialWorld"] = world
        #expect(throws: ReplayPlayer.ReplayError.self) { try ReplayPlayer.replay(try decode(badWorld), ticks: 0) }

        // Terrain storage that does not match the arena.
        var terrain = try #require((json["initialWorld"] as? [String: Any])?["terrain"] as? [String: Any])
        terrain["cells"] = [["kind": 0, "quadrantMask": 0]]
        var torn = json
        var tornWorld = try #require(json["initialWorld"] as? [String: Any])
        tornWorld["terrain"] = terrain
        torn["initialWorld"] = tornWorld
        #expect(throws: ReplayPlayer.ReplayError.self) { try ReplayPlayer.replay(try decode(torn), ticks: 1) }

        // Duplicate command envelopes.
        var log = try #require(json["commandLog"] as? [[String: Any]])
        log.append(log[0])
        var duplicated = json; duplicated["commandLog"] = log
        #expect(throws: ReplayPlayer.ReplayError.duplicateCommandTick(tick: 0)) {
            try ReplayPlayer.replay(try decode(duplicated), ticks: 1)
        }

        // Absurd tick counts are malformed input, not a ten-hour job.
        #expect(throws: ReplayPlayer.ReplayError.invalidTickCount(Int.max)) {
            try ReplayPlayer.replay(session.recording, ticks: Int.max)
        }
        #expect(throws: ReplayPlayer.ReplayError.invalidTickCount(-1)) {
            try ReplayPlayer.replay(session.recording, ticks: -1)
        }
        _ = json
    }

    /// R5-01: validation is total over decoded integers — extreme values in
    /// rules, positions and the arena are rejected, never trapped on.
    @Test func extremeIntegersAreRejectedByValidationWithoutTrapping() throws {
        var session = MovementLabSession()
        session.advance(holding: nil, normalFire: true)
        let data = try JSONEncoder().encode(session.recording)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        func decode(_ json: [String: Any]) throws -> ReplayRecording {
            try JSONDecoder().decode(ReplayRecording.self, from: JSONSerialization.data(withJSONObject: json))
        }
        func mutated(_ path: [Any], _ value: Any) throws -> ReplayRecording {
            func set(_ node: Any, _ path: ArraySlice<Any>) -> Any {
                guard let key = path.first else { return value }
                if let index = key as? Int, var array = node as? [Any] {
                    array[index] = set(array[index], path.dropFirst()); return array
                }
                var dict = node as! [String: Any]
                dict[key as! String] = set(dict[key as! String] ?? [:], path.dropFirst())
                return dict
            }
            return try decode(set(json, path[...]) as! [String: Any])
        }
        // Movement inset at Int.max (the reported crash).
        #expect(throws: ReplayPlayer.ReplayError.self) {
            try ReplayPlayer.replay(try mutated(["movement", "collisionInsetSubunits"], Int.max), ticks: 0)
        }
        // A tank position at Int.max (the reported crash).
        #expect(throws: ReplayPlayer.ReplayError.self) {
            try ReplayPlayer.replay(try mutated(["initialWorld", "tanks", 0, "positionSubunits", "x"], Int.max), ticks: 0)
        }
        // Projectile extent at Int.max: outside the documented domain.
        #expect(throws: ReplayPlayer.ReplayError.self) {
            try ReplayPlayer.replay(try mutated(["weapons", "projectileHalfExtentSubunits"], Int.max), ticks: 1)
        }
        // Arena dimensions at Int.max: rejected before any product is formed.
        #expect(throws: ReplayPlayer.ReplayError.self) {
            try ReplayPlayer.replay(try mutated(["initialWorld", "terrain", "arena", "cellsWide"], Int.max), ticks: 0)
        }
        // Base speed at Int.max with a large multiplier: bounded before multiplying.
        #expect(throws: ReplayPlayer.ReplayError.self) {
            try ReplayPlayer.replay(try mutated(["movement", "baseSpeedSubunitsPerSecond"], Int.max), ticks: 0)
        }
        // The validators themselves never trap on such worlds and rules.
        let hostile = try mutated(["initialWorld", "tanks", 0, "positionSubunits", "x"], Int.max)
        #expect(!WorldInvariants.violations(in: hostile.initialWorld).isEmpty)
        var rules = MovementRuleset.provisional
        rules.collisionInsetSubunits = Int.max
        rules.baseSpeedSubunitsPerSecond = Int.max
        rules.speedMultipliersPermille = [Int.max, 1, 1, 1]
        #expect(!rules.validationIssues().isEmpty)
        var weapons = WeaponRuleset.provisional
        weapons.projectileHalfExtentSubunits = Int.max
        #expect(!weapons.validationIssues().isEmpty)
    }

    /// R6-01 / R6-02: signed extremes and the counters the simulation
    /// increments are admitted only inside documented domains — Int.min in
    /// a signed field and Int.max in a spawn cursor are rejected before any
    /// tick, and the validators never trap on them.
    @Test func signedExtremesAndIncrementedCountersAreRejected() throws {
        var world = try StageLoader.loadWorld(at: vs01URL)
        var minimum = world
        minimum.withTank(entityID: minimum.player(.one)!.tankEntityID!) { $0.slideMomentumSubunits = Int.min }
        #expect(!WorldInvariants.violations(in: minimum).isEmpty)
        #expect(throws: ReplayPlayer.ReplayError.self) {
            try ReplayPlayer.replay(ReplayRecording(initialWorld: minimum), ticks: 0)
        }

        var cursor = world
        cursor.stage?.nextSpawnPointIndex = Int.max
        cursor.stage?.enemyStartDelayTicks = 0
        #expect(!WorldInvariants.violations(in: cursor).isEmpty)
        #expect(throws: ReplayPlayer.ReplayError.self) {
            try ReplayPlayer.replay(ReplayRecording(initialWorld: cursor), ticks: 1)
        }

        var telegraph = world
        telegraph.stage?.enemyStartDelayTicks = 0
        for _ in 0..<2 { Simulation.step(&telegraph, commands: []) } // a telegraph exists
        #expect(!telegraph.spawnTelegraphs.isEmpty)
        // The telegraph list is core-internal: corrupt it through the JSON.
        let encoded = try JSONEncoder().encode(ReplayRecording(initialWorld: telegraph))
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var initial = try #require(json["initialWorld"] as? [String: Any])
        var telegraphs = try #require(initial["spawnTelegraphs"] as? [[String: Any]])
        telegraphs[0]["spawnPointIndex"] = Int.max
        initial["spawnTelegraphs"] = telegraphs
        json["initialWorld"] = initial
        let corrupt = try JSONDecoder().decode(ReplayRecording.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        #expect(!WorldInvariants.violations(in: corrupt.initialWorld).isEmpty)
        #expect(throws: ReplayPlayer.ReplayError.self) { try ReplayPlayer.replay(corrupt, ticks: 200) }

        var tick = world
        tick.tick = Int.max
        #expect(!WorldInvariants.violations(in: tick).isEmpty)
        var ids = world
        ids.nextEntityID = Int.max
        #expect(!WorldInvariants.violations(in: ids).isEmpty)

        // The admitted headroom survives the worst legal case: a cursor at
        // its domain maximum steps without trapping.
        world.stage?.nextSpawnPointIndex = WorldInvariants.maxCount
        world.stage?.enemyStartDelayTicks = 0
        #expect(WorldInvariants.violations(in: world).isEmpty)
        _ = try ReplayPlayer.replay(ReplayRecording(initialWorld: world), ticks: 60)
    }
}
