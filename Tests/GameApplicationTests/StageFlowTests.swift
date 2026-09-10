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
        // delay 100 + text 21 + hold 145 + fade 30 + panel-in 30 + panel-hold 110.
        #expect(ticks == 436)
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
    }
}
