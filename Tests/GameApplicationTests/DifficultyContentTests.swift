import Foundation
import Testing
import GameCore
@testable import GameApplication

/// ADR-0015: difficulty content, its application at build time, and the
/// replay header that names it.
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private func difficultyURL(_ id: String) -> URL { repoRoot.appendingPathComponent("Content/difficulties/\(id).json") }
private let vs03URL = repoRoot.appendingPathComponent("Content/stages/frontier_03_desert_stairs.json")
private let vs01URL = repoRoot.appendingPathComponent("Content/stages/frontier_01_first_defense.json")

@Suite struct DifficultyContentTests {
    @Test func theThreePresetsLoadAndDifferAsThePlanIntends() throws {
        let casual = try DifficultyLoader.load(at: difficultyURL("casual"))
        let standard = try DifficultyLoader.load(at: difficultyURL("standard"))
        let veteran = try DifficultyLoader.load(at: difficultyURL("veteran"))
        #expect(standard.enemyBehavior == .standard && standard.composition == .baseline && standard.alliedBaseDamage)
        #expect(!casual.alliedBaseDamage && veteran.alliedBaseDamage) // ADR-0005: Off / On / On
        #expect(casual.composition == .forgiving && veteran.composition == .advanced)
        #expect(casual.enemyBehavior.decisionIntervalTicks > standard.enemyBehavior.decisionIntervalTicks)
        #expect(veteran.enemyBehavior.decisionIntervalTicks < standard.enemyBehavior.decisionIntervalTicks)
        #expect(casual.telegraphTicksPercent > 100 && veteran.telegraphTicksPercent >= 100)
        #expect(casual.enemySpecialAmmoPercent == 70 && veteran.enemySpecialAmmoPercent == 140)
        for def in [casual, standard, veteran] { #expect(DifficultyValidator.validate(def).isEmpty) }
    }

    @Test func invalidDifficultiesAreRefused() {
        var def = DifficultyDefinition.standard
        def.id = "nightmare"
        #expect(DifficultyValidator.validate(def).contains { $0.contains("unknown difficulty id") })
        def.id = "veteran"; def.telegraphTicksPercent = 5; def.enemyBehavior.wanderPercent = 200
        #expect(DifficultyValidator.validate(def).count == 2)
        #expect(throws: StageBuilder.BuildError.self) {
            try StageBuilder.build(try StageLoader.loadDefinition(at: vs01URL), difficulty: def)
        }
    }

    @Test func compositionVariantsAndTheTelegraphFloor() {
        let queue = ["normal_a", "rapid_b", "normal_c", "ap_d", "fire_a", "mine_b", "normal_a"]
        var forgiving = DifficultyDefinition.standard
        forgiving.composition = .forgiving
        #expect(forgiving.apply(toComposition: queue) == ["normal_a", "rapid_b", "normal_a", "ap_b", "fire_a", "mine_b", "normal_a"])
        var advanced = DifficultyDefinition.standard
        advanced.composition = .advanced // every third A/B entry is promoted
        #expect(advanced.apply(toComposition: queue) == ["normal_a", "rapid_b", "normal_c", "ap_d", "fire_c", "mine_b", "normal_a"])
        #expect(DifficultyDefinition.standard.apply(toComposition: queue) == queue)
        var slow = DifficultyDefinition.standard
        slow.telegraphTicksPercent = 140
        #expect(slow.telegraphTicks(authored: 45) == 63)
        var fast = DifficultyDefinition.standard
        fast.telegraphTicksPercent = 10
        #expect(fast.telegraphTicks(authored: 60) == 45) // never below the fairness floor
    }

    @Test func theBuilderAppliesTheDifficultyAndTheAuthoredPhases() throws {
        let def = try StageLoader.loadDefinition(at: vs03URL)
        #expect(def.directorPhases?.map(\.id) == ["elite_minelayer"])
        let casual = try DifficultyLoader.load(at: difficultyURL("casual"))
        let veteran = try DifficultyLoader.load(at: difficultyURL("veteran"))
        let standardWorld = try StageBuilder.build(def)
        let casualWorld = try StageBuilder.build(def, difficulty: casual)
        let veteranWorld = try StageBuilder.build(def, difficulty: veteran)
        #expect(standardWorld.stage?.enemyBehavior == .standard)
        #expect(casualWorld.stage?.enemyBehavior == casual.enemyBehavior)
        #expect(casualWorld.stage?.telegraphTicks == casual.telegraphTicks(authored: def.telegraphTicks))
        #expect(casualWorld.stage?.spawnQueue.allSatisfy { !$0.hasSuffix("_c") && !$0.hasSuffix("_d") } == true)
        #expect(veteranWorld.stage?.spawnQueue.contains { $0.hasSuffix("_c") || $0.hasSuffix("_d") } == true)
        #expect(standardWorld.stage?.spawnQueue.count == casualWorld.stage?.spawnQueue.count)
        let phase = try #require(standardWorld.stage?.directorPhases.first)
        #expect(phase.reinforcements == ["mine_c", "ap_c", "ap_c"] && phase.maxAliveEnemies == 6 && phase.repairsBase)
        #expect(casualWorld.stage?.directorPhases.first?.reinforcements == ["mine_a", "ap_a", "ap_a"])
        #expect(standardWorld.checksum() != casualWorld.checksum())
        #expect(WorldInvariants.violations(in: veteranWorld).isEmpty)
        // Content: invalid phases are reported by the validator.
        var broken = def
        broken.directorPhases = [DirectorPhase(id: "", afterSpawned: 999, reinforcements: ["dragon"], maxAliveEnemies: 0)]
        let issues = StageValidator.validate(broken)
        #expect(issues.contains { $0.contains("without id") } && issues.contains { $0.contains("outside 0…") }
                && issues.contains { $0.contains("dragon") } && issues.contains { $0.contains("max_alive_enemies") })
    }

    @Test func theRunAndTheRecordingNameTheDifficulty() throws {
        let campaign = CampaignDefinition(id: "c", displayNameKey: "k", stageIDs: ["frontier_01_first_defense"])
        let run = CampaignRun(campaign: campaign, difficultyID: "veteran")
        #expect(run.difficultyID == "veteran" && run.validationIssues.isEmpty)
        let data = try JSONEncoder().encode(run)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "difficultyID")
        let legacy = try JSONDecoder().decode(CampaignRun.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.difficultyID == "standard") // runs saved before difficulty existed
        let world = try StageLoader.loadWorld(at: vs01URL)
        let session = MovementLabSession(world: world, stageID: run.stageID, sessionState: run.checkpoint, difficultyID: "veteran")
        #expect(session.recording.difficultyID == "veteran")
        let decoded = try JSONDecoder().decode(ReplayRecording.self, from: JSONEncoder().encode(session.recording))
        #expect(decoded.difficultyID == "veteran" && decoded == session.recording)
    }
}
