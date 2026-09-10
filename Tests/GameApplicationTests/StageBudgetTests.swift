import Foundation
import GameCore
import Testing
@testable import GameApplication

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let vs01URL = repoRoot.appendingPathComponent("Content/stages/frontier_01_first_defense.json")

/// R15-02: content admission rejects what the builder could not build or
/// the world invariants would refuse — before any allocation.
@Suite struct StageBudgetTests {
    private func definition(_ mutate: (inout [String: Any]) -> Void) throws -> StageDefinition {
        let data = try Data(contentsOf: vs01URL)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&json)
        return try StageLoader.decode(JSONSerialization.data(withJSONObject: json))
    }

    private func compositionKey(_ json: [String: Any]) -> String {
        json["enemy_composition"] != nil ? "enemy_composition" : "enemyComposition"
    }

    @Test func aSingleHugeCountIsRejectedBeforeAnyAllocation() throws {
        let def = try definition { json in
            let key = self.compositionKey(json)
            var entries = json[key] as? [[String: Any]] ?? []
            #expect(!entries.isEmpty)
            entries = [entries[0]]
            entries[0]["count"] = Int.max // does not overflow a one-term sum
            json[key] = entries
        }
        let issues = StageValidator.validate(def)
        #expect(issues.contains { $0.contains("exceeds the stage budget") })
        #expect(throws: (any Error).self) { try StageBuilder.build(def) } // never reaches the allocation loop
    }

    @Test func aTotalAboveTheBudgetIsRejected() throws {
        let def = try definition { json in
            let key = self.compositionKey(json)
            var entries = json[key] as? [[String: Any]] ?? []
            entries[0]["count"] = StageValidator.maxEnemiesPerStage
            entries.append(["archetype": entries[0]["archetype"]!, "count": 1])
            json[key] = entries
        }
        #expect(StageValidator.validate(def).contains { $0.contains("total") && $0.contains("exceeds") })
    }

    @Test func timersAndCapsBeyondTheWorldDomainAreRejected() throws {
        let delayKey = "initial_enemy_delay_ticks"
        let def = try definition { json in
            json[json[delayKey] != nil ? delayKey : "initialEnemyDelayTicks"] = WorldInvariants.maxTicks + 1
            json[json["telegraph_ticks"] != nil ? "telegraph_ticks" : "telegraphTicks"] = WorldInvariants.maxTicks + 1
            json[json["max_alive_enemies"] != nil ? "max_alive_enemies" : "maxAliveEnemies"] = WorldInvariants.maxCount + 1
        }
        let issues = StageValidator.validate(def)
        #expect(issues.contains { $0.contains("initial_enemy_delay_ticks") && $0.contains("out of domain") })
        #expect(issues.contains { $0.contains("telegraph_ticks") && $0.contains("out of domain") })
        #expect(issues.contains { $0.contains("max_alive_enemies") && $0.contains("out of domain") })
    }

    @Test func theShippedStageStaysWithinTheBudget() throws {
        let def = try StageLoader.decode(Data(contentsOf: vs01URL))
        #expect(StageValidator.validate(def).isEmpty)
        let world = try StageBuilder.build(def)
        #expect(WorldInvariants.violations(in: world).isEmpty)
    }
}
