import GameCore
import Testing
@testable import GameApplication

/// ADR-0011 stage transitions: the flow is a pure tick timeline that gates
/// the simulation and emits cues at the reference's moments.
@Suite struct StageFlowTests {
    @Test func introTimelineMatchesTheReferenceAndGatesTheSimulation() {
        var flow = StageFlow(arenaCellsWide: 26, arenaCellsHigh: 26)
        #expect(flow.phase == .card && !flow.allowsSimulation && flow.revealStep == nil)
        #expect(flow.revealSteps == 13)
        var cues: [StageFlow.Cue] = []
        var ticks = 0
        while flow.phase != .playing {
            cues += flow.advance()
            ticks += 1
            #expect(ticks < 1000, "intro never ends")
        }
        // card 138 + reveal 26 + title-out 24 = 188 ticks ≈ 3.1 s (reference 8.9 s → 12.0 s).
        #expect(ticks == 188)
        #expect(cues == [.cardTitle, .reveal])
        #expect(flow.allowsSimulation && flow.revealStep == 13 && !flow.showsTitle)
    }

    @Test func revealGrowsMonotonicallyToTheFullArena() {
        var flow = StageFlow(arenaCellsWide: 26, arenaCellsHigh: 20)
        while flow.phase != .reveal { flow.advance() }
        var last = -1
        while flow.phase == .reveal {
            let step = try! #require(flow.revealStep)
            #expect(step >= last && step <= flow.revealSteps)
            last = step
            flow.advance()
        }
        #expect(flow.revealStep == flow.revealSteps)
    }

    @Test func outroWonRunsToAutomaticContinue() {
        var flow = StageFlow.playing()
        #expect(flow.allowsSimulation)
        flow.advance() // playing is untimed
        #expect(flow.phase == .playing)
        flow.beginOutro(won: true)
        #expect(flow.phase == .outroDelay && !flow.allowsSimulation && flow.outcome == .won)
        var cues: [StageFlow.Cue] = []
        var ticks = 0
        while flow.phase != .finished {
            cues += flow.advance()
            ticks += 1
            #expect(ticks < 2000)
        }
        // delay 48 + stamp 24 + hold 84 + curtain 42 + card pop 21 + panel-hold 110.
        #expect(ticks == 329)
        #expect(cues.prefix(2) == [.outcomeText, .fade])
        // No tally rows: the panel still lists its total line.
        #expect(cues.filter { if case .panelRow = $0 { return true }; return false }.count == 1)
        #expect(flow.wantsAutomaticContinue && flow.showsPanel && flow.panelRowsVisible == 1)
        // A decided flow stays decided.
        flow.beginOutro(won: false)
        #expect(flow.outcome == .won)
    }

    @Test func outroLostHoldsThePanelForThePlayer() {
        var flow = StageFlow.playing()
        flow.beginOutro(won: false)
        for _ in 0..<600 { flow.advance() }
        #expect(flow.phase == .finished && flow.outcome == .lost)
        #expect(!flow.wantsAutomaticContinue && flow.showsPanel && flow.showsOutcomeText)
    }

    @Test func panelRowsAppearOnTheTallyCadence() {
        var flow = StageFlow.playing()
        flow.beginOutro(won: true, resultRows: 7) // 7 archetypes + the total line
        while flow.phase != .panelHold { flow.advance() }
        #expect(flow.panelRowsVisible == 0)
        var rows: [Int] = []
        var seen = 0
        while flow.phase == .panelHold {
            for case .panelRow(let row) in flow.advance() { rows.append(row) }
            seen = max(seen, flow.panelRowsVisible)
            #expect(flow.panelRowsVisible == rows.count) // a row is visible exactly when its cue fired
        }
        #expect(rows == Array(0..<8) && seen == 8)
    }

    /// R11-05: the results capacity follows the tally — every row and the
    /// total line appear, with the settle time after the last, whatever the
    /// archetype count.
    @Test(arguments: [0, 2, 8, 9, 24])
    func resultsCapacityFollowsTheTally(archetypes: Int) {
        var flow = StageFlow.playing()
        flow.beginOutro(won: true, resultRows: archetypes)
        #expect(flow.panelRows == archetypes + 1)
        var rowCues: [Int] = []
        var lastRowTick = 0, holdTicks = 0
        while flow.phase != .finished {
            let inHold = flow.phase == .panelHold
            for case .panelRow(let row) in flow.advance() {
                rowCues.append(row)
                lastRowTick = holdTicks
            }
            if inHold { holdTicks += 1 }
        }
        #expect(rowCues == Array(0...archetypes))
        #expect(flow.panelRowsVisible == archetypes + 1)
        #expect(holdTicks - lastRowTick >= flow.durations.panelSettle)
        #expect(holdTicks >= flow.durations.panelHold)
    }

    /// Designed outro (2026-09-10): the cover advances from the arena edges
    /// to the centre during `outroFade`, monotonically, and stays fully
    /// closed for the results; the playfield is open before that.
    @Test func theOutroCoverClosesMonotonicallyAndStaysClosed() {
        var flow = StageFlow(arenaCellsWide: 56, arenaCellsHigh: 27)
        while flow.phase != .playing { flow.advance() }
        #expect(flow.coverStep == nil && !flow.isCovered)
        flow.beginOutro(won: false, lossReason: "base_destroyed")
        while flow.phase != .outroFade {
            #expect(flow.coverStep == nil && !flow.isCovered)
            flow.advance()
        }
        var last = -1
        while flow.phase == .outroFade {
            let step = try! #require(flow.coverStep)
            #expect(step >= last && step <= flow.revealSteps)
            last = step
            #expect(!flow.isCovered)
            flow.advance()
        }
        #expect(flow.coverStep == flow.revealSteps && flow.isCovered && flow.phase == .panelIn)
        for _ in 0..<600 { flow.advance() }
        #expect(flow.phase == .finished && flow.coverStep == flow.revealSteps && flow.isCovered)
    }

    /// ADR-0012: the reward line follows the total line by `rewardDelay`
    /// on a won stage with a clear bonus, with its own cue; the hold covers
    /// it. A lost stage or a stage without a bonus shows no reward line.
    @Test func theRewardLineFollowsTheTotalWithItsOwnCue() {
        var flow = StageFlow.playing()
        flow.beginOutro(won: true, resultRows: KillTally.tableRows, rewardLine: true)
        #expect(flow.panelRows == 5 && flow.hasRewardLine)
        while flow.phase != .panelHold { flow.advance() }
        var cues: [StageFlow.Cue] = []
        var holdTicks = 0, rewardTick: Int?
        while flow.phase == .panelHold {
            #expect(flow.showsReward == (rewardTick != nil))
            let fired = flow.advance()
            if fired.contains(.reward) { rewardTick = holdTicks }
            cues += fired
            holdTicks += 1
        }
        let interval = flow.durations.panelRowInterval
        #expect(cues == [.panelRow(0), .panelRow(1), .panelRow(2), .panelRow(3), .panelRow(4), .reward])
        #expect(rewardTick == 4 * interval + flow.durations.rewardDelay)
        #expect(holdTicks - (rewardTick ?? 0) >= flow.durations.panelSettle)
        #expect(flow.phase == .finished && flow.showsReward && flow.panelRowsVisible == 5)

        var plain = StageFlow.playing()
        plain.beginOutro(won: true, resultRows: KillTally.tableRows)
        var plainCues: [StageFlow.Cue] = []
        while plain.phase != .finished { plainCues += plain.advance() }
        #expect(!plainCues.contains(.reward) && !plain.showsReward)

        var lost = StageFlow.playing()
        lost.beginOutro(won: false, resultRows: KillTally.tableRows, lossReason: "base_destroyed", rewardLine: true)
        #expect(!lost.hasRewardLine)
        var lostCues: [StageFlow.Cue] = []
        while lost.phase != .finished { lostCues += lost.advance() }
        #expect(!lostCues.contains(.reward) && !lost.showsReward)
    }

    /// R15-05: the loss reason travels with the outcome; a win carries none.
    @Test func lossReasonTravelsWithTheOutcome() {
        var lost = StageFlow.playing()
        lost.beginOutro(won: false, resultRows: 1, lossReason: "player_eliminated")
        #expect(lost.outcome == .lost && lost.lossReason == "player_eliminated")
        var won = StageFlow.playing()
        won.beginOutro(won: true, resultRows: 1, lossReason: "ignored")
        #expect(won.outcome == .won && won.lossReason == nil)
    }

    @Test func outroIsOnlyEnteredFromPlay() {
        var flow = StageFlow(arenaCellsWide: 26, arenaCellsHigh: 26)
        flow.beginOutro(won: true) // still on the card
        #expect(flow.phase == .card && flow.outcome == nil)
    }
}

@Suite struct KillTallyTests {
    @Test func countsEnemyKillsByArchetypeInFirstKillOrder() {
        var world = WorldState(terrain: TerrainGrid(arena: .universal), seed: 1)
        let cell = SpatialUnits.subunitsPerCell
        let a = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "light",
                                positionSubunits: Vec2i(x: 2 * cell, y: 2 * cell), facing: .down)
        let b = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "heavy",
                                positionSubunits: Vec2i(x: 6 * cell, y: 2 * cell), facing: .down)
        let c = world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: "light",
                                positionSubunits: Vec2i(x: 10 * cell, y: 2 * cell), facing: .down)
        let player = world.spawnTank(teamID: 1, ownerPlayerID: .one, archetypeID: "player",
                                     positionSubunits: Vec2i(x: 10 * cell, y: 10 * cell), facing: .up)
        var tally = KillTally()
        tally.remember(world)
        let origin = Vec2i(x: 0, y: 0)
        tally.observe([.tankDestroyed(entityID: b, ownerPlayerID: nil, position: origin),
                       .tankDestroyed(entityID: player, ownerPlayerID: .one, position: origin), // the player: not a kill
                       .tankDestroyed(entityID: a, ownerPlayerID: nil, position: origin),
                       .tankDestroyed(entityID: 999, ownerPlayerID: nil, position: origin)])   // unknown entity ignored
        tally.observe([.tankDestroyed(entityID: c, ownerPlayerID: nil, position: origin),
                       .tankDestroyed(entityID: a, ownerPlayerID: nil, position: origin)])     // counted once
        #expect(tally.rows.map(\.archetypeID) == ["heavy", "light"])
        #expect(tally.byArchetype == ["heavy": 1, "light": 2])
        #expect(tally.total == 3)
        #expect(tally.byCategory == [3, 0, 0, 0, 0, 0, 0, 0]) // unknown archetypes count in the fodder row
    }

    /// ADR-0012: the results table groups kills by reward category — four
    /// rows of two, multiplied by the row — and the weighted total is the
    /// reference's "总计".
    @Test func groupsKillsByRewardCategoryWithRowMultipliers() {
        var world = WorldState(terrain: TerrainGrid(arena: .universal), seed: 2)
        let cell = SpatialUnits.subunitsPerCell
        var ids: [Int] = []
        for (i, archetype) in ["normal_a", "normal_a", "normal_c", "rapid_b", "fire_a", "ap_d"].enumerated() {
            ids.append(world.spawnTank(teamID: 2, ownerPlayerID: nil, archetypeID: archetype,
                                       positionSubunits: Vec2i(x: (2 + 4 * i) * cell, y: 2 * cell), facing: .down))
        }
        var tally = KillTally()
        tally.remember(world)
        tally.observe(ids.map { .tankDestroyed(entityID: $0, ownerPlayerID: nil, position: Vec2i(x: 0, y: 0)) })
        #expect(tally.byCategory == [2, 1, 1, 0, 0, 1, 0, 1])
        #expect(tally.rowCounts(0) == (2, 1) && tally.rowSubtotal(0) == 3)
        #expect(tally.rowCounts(1) == (1, 0) && tally.rowSubtotal(1) == 2)
        #expect(tally.rowCounts(2) == (0, 1) && tally.rowSubtotal(2) == 3)
        #expect(tally.rowCounts(3) == (0, 1) && tally.rowSubtotal(3) == 4)
        #expect(tally.weightedTotal == 12 && tally.total == 6)
        #expect(KillTally().weightedTotal == 0)
    }
}
