import Foundation
import GameCore
import Testing
@testable import GameApplication

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let vs01URL = repoRoot.appendingPathComponent("Content/stages/frontier_01_first_defense.json")

/// R15-01: every entity id and id reference in a decoded world lies in
/// `1..<nextEntityID` before the simulation does arithmetic on it. A world
/// with an out-of-domain id is refused at admission — never replayed into
/// a trap.
@Suite struct EntityIDDomainTests {
    /// One valid stage-world snapshot per entity kind, captured at the
    /// first tick where that collection is non-empty: projectiles from
    /// routine fire, a flame patch from the "fire" special, a mine from the
    /// "mine" special, spawn telegraphs from the stage's first wave.
    private func snapshots() throws -> [String: WorldState] {
        var session = MovementLabSession(world: try StageLoader.loadWorld(at: vs01URL))
        session.debugSelectSpecialWeapon("fire")
        var found: [String: WorldState] = [:]
        for i in 0..<420 {
            if i == 150 { session.debugSelectSpecialWeapon("mine") }
            session.advance(holding: i % 90 < 45 ? .up : .right,
                            normalFire: i % 20 == 3, specialFire: i == 2 || i == 152)
            let world = session.world
            guard WorldInvariants.violations(in: world).isEmpty else { continue }
            let present: [(String, Bool)] = [
                ("tanks", !world.tanks.isEmpty), ("projectiles", !world.projectiles.isEmpty),
                ("spawnTelegraphs", !world.spawnTelegraphs.isEmpty), ("fireHazards", !world.fireHazards.isEmpty),
                ("mines", !world.mines.isEmpty), ("pickups", !world.pickups.isEmpty),
                ("enemies", world.tanks.contains { $0.teamID != 1 }),
            ]
            for (kind, has) in present where has && found[kind] == nil { found[kind] = world }
        }
        return found
    }

    private func json(_ world: WorldState) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
    }

    private func decode(_ json: [String: Any]) throws -> WorldState {
        try JSONDecoder().decode(WorldState.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func violations(_ json: [String: Any]) throws -> [String] {
        WorldInvariants.violations(in: try decode(json))
    }

    @Test func decodedOutOfDomainIDsAreRefusedForEveryEntityKind() throws {
        let worlds = try snapshots()
        let kinds = ["tanks", "projectiles", "spawnTelegraphs", "fireHazards", "mines", "pickups"]
        var covered: [String] = []
        for kind in kinds {
            guard let world = worlds[kind] else { continue }
            let base = try json(world)
            var entities = try #require(base[kind] as? [[String: Any]])
            covered.append(kind)
            for bad in [Int.min / 2, -1, 0, world.nextEntityID, Int.max / 2] {
                entities[0]["entityID"] = bad
                var mutated = base
                mutated[kind] = entities
                let issues = try violations(mutated)
                #expect(issues.contains { $0.contains("outside 1..<nextEntityID") },
                        "\(kind) id \(bad) admitted: \(issues)")
            }
        }
        #expect(covered.contains("tanks") && covered.contains("projectiles") && covered.contains("spawnTelegraphs"))
        #expect(covered.contains("fireHazards") && covered.contains("mines"))
    }

    @Test func outOfDomainReferencesAreRefusedButDeadOwnersAreNot() throws {
        let worlds = try snapshots()
        var covered = 0
        for kind in ["projectiles", "fireHazards", "mines"] {
            guard let world = worlds[kind] else { continue }
            let base = try json(world)
            var entities = try #require(base[kind] as? [[String: Any]])
            covered += 1
            entities[0]["ownerEntityID"] = Int.min / 2
            var mutated = base
            mutated[kind] = entities
            #expect(try violations(mutated).contains { $0.contains("owner entity id") }, "\(kind)")
            // A dead owner (an id below nextEntityID with no live tank) is
            // legal ordnance, and −1 is the documented "no owner" sentinel.
            for legal in [world.nextEntityID - 1, -1] {
                entities[0]["ownerEntityID"] = legal
                mutated[kind] = entities
                #expect(!(try violations(mutated).contains { $0.contains("owner entity id") }), "\(kind) owner \(legal)")
            }
        }
        #expect(covered == 3)
        let world = try #require(worlds["projectiles"])
        var base = try json(world)
        var projectiles = try #require(base["projectiles"] as? [[String: Any]])
        projectiles[0]["hitTankIDs"] = [-7]
        base["projectiles"] = projectiles
        #expect(try violations(base).contains { $0.contains("hit entity id") })
    }

    @Test func theBoundaryIsExactlyNextEntityID() throws {
        let world = try #require(try snapshots()["projectiles"])
        var base = try json(world)
        let ids = (["tanks", "projectiles", "spawnTelegraphs", "fireHazards", "mines", "pickups"]
            .flatMap { base[$0] as? [[String: Any]] ?? [] }
            .compactMap { $0["entityID"] as? Int })
        let top = try #require(ids.max())
        base["nextEntityID"] = top + 1
        #expect(try violations(base).isEmpty)
        base["nextEntityID"] = top
        #expect(try violations(base).contains { $0.contains("outside 1..<nextEntityID") })
    }

    /// PI's round-15 reproduction: an enemy with `entityID = Int.min / 2`
    /// in a playing stage used to pass admission and trap in the AI
    /// cadence arithmetic one tick into playback.
    @Test func negativeEnemyIDIsRejectedAtReplayAdmissionNotTrapped() throws {
        let world = try #require(try snapshots()["enemies"]) // a live enemy in a playing stage
        var base = try json(world)
        var tanks = try #require(base["tanks"] as? [[String: Any]])
        let enemyIndex = try #require(tanks.firstIndex { ($0["teamID"] as? Int) != 1 })
        tanks[enemyIndex]["entityID"] = Int.min / 2
        base["tanks"] = tanks
        let corrupted = try decode(base)
        let recording = ReplayRecording(initialWorld: corrupted) // checksum consistent with the corrupted world
        #expect(throws: ReplayPlayer.ReplayError.self) { try ReplayPlayer.replay(recording, ticks: 1) }
        do {
            _ = try ReplayPlayer.replay(recording, ticks: 1)
        } catch let ReplayPlayer.ReplayError.invalidInitialWorld(issues) {
            #expect(issues.contains { $0.contains("outside 1..<nextEntityID") })
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
