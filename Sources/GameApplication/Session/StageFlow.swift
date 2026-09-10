import GameCore

/// The stage's presentation timeline around the simulation: an intro card,
/// the playfield reveal, play, then the outcome text and the results panel.
/// The intro follows the reference's measured transitions (ADR-0011); the
/// outro is a designed transition since the owner's 2026-09-10 late-evening
/// feedback ("可以设计一个好一些的转场"): freeze, the outcome title stamps into
/// the centre, the playfield closes under a shrinking curtain while the
/// title glides to the top, then the results card pops in centred.
/// Tick-driven at
/// the simulation rate so the controller advances it in lockstep with the
/// clock; the simulation steps only while `allowsSimulation`. A pure value:
/// no timers, no presentation types — the scene and view read phase and
/// progress from it, and the controller maps `Cue`s to sounds.
public struct StageFlow: Equatable, Sendable {
    public enum Phase: Equatable, Sendable, CaseIterable {
        /// Title card: the stage title slides in from the left, then holds.
        case card
        /// The playfield appears as a cross of cell strips growing from the
        /// arena centre.
        case reveal
        /// The title flips away over the visible playfield.
        case titleOut
        case playing
        /// Outcome known, world frozen, the decisive effect plays out.
        case outroDelay
        /// The outcome title stamps into the centre (flash; shake on a loss).
        case outroText
        /// The title holds at the centre.
        case outroHold
        /// The curtain closes over the playfield from the edges to the
        /// centre (`coverStep`) while the title glides to the top.
        case outroFade
        /// The results card pops in at the centre.
        case panelIn
        /// Results readable; tally rows count up.
        case panelHold
        /// Timeline complete: a won stage continues by itself, a lost stage
        /// waits for the player.
        case finished
    }

    /// Presentation moments the controller turns into sounds.
    public enum Cue: Equatable, Sendable {
        case cardTitle
        case reveal
        case outcomeText
        case fade
        /// Row `index` of the results table becomes visible.
        case panelRow(Int)
        /// The "Reward +N" line appears (a won stage with a clear bonus).
        case reward
    }

    /// Phase lengths in ticks (60 Hz). Intro (reference timings): card
    /// 2.3 s, reveal 0.45 s, title-out 0.4 s. Outro (designed): 0.8 s
    /// freeze, 0.4 s stamp, 1.4 s hold, 0.7 s curtain close, 0.35 s card
    /// pop, then the tally.
    public struct Durations: Equatable, Sendable {
        public var card = 138
        public var reveal = 26
        public var titleOut = 24
        public var outroDelay = 48
        public var outroText = 24
        public var outroHold = 84
        public var outroFade = 42
        public var panelIn = 21
        public var panelHold = 110
        /// Ticks between tally rows during `panelHold`.
        public var panelRowInterval = 12
        /// Time the last row stays before the timeline ends.
        public var panelSettle = 30
        /// Ticks after the total line before the reward line (reference:
        /// the reward text follows the finished tally by ≈0.2–0.4 s).
        public var rewardDelay = 18
        public init() {}
    }

    public private(set) var phase: Phase
    public private(set) var ticksInPhase = 0
    /// `.won` / `.lost` once known; nil while undecided.
    public private(set) var outcome: StagePhase?
    /// The simulation's loss reason (`stageLost(reason:)`: "base_destroyed",
    /// "player_eliminated"), kept so the outcome text can be truthful.
    public private(set) var lossReason: String?
    public let durations: Durations
    /// Cross-reveal extent: strips from the centre out to this many cells
    /// cover the whole arena.
    public let revealSteps: Int
    /// Results rows the panel must show: one per tally row plus the total
    /// line, fixed when the outro begins so `panelHold` is long enough for
    /// all of them (R11-05: never a cap independent of the tally).
    public private(set) var panelRows = 1
    /// Whether the panel ends with a reward line (won with a clear bonus).
    public private(set) var hasRewardLine = false

    /// A stage that opens with the intro card.
    public init(arenaCellsWide: Int, arenaCellsHigh: Int, durations: Durations = Durations()) {
        phase = .card
        self.durations = durations
        revealSteps = max(1, (max(arenaCellsWide, arenaCellsHigh) + 1) / 2)
    }

    /// Straight into play (lab worlds, tests).
    public static func playing(durations: Durations = Durations()) -> StageFlow {
        var flow = StageFlow(arenaCellsWide: 1, arenaCellsHigh: 1, durations: durations)
        flow.phase = .playing
        return flow
    }

    public var allowsSimulation: Bool { phase == .playing }

    /// Whether the intro curtain covers the playfield at all.
    public var isIntro: Bool { phase == .card || phase == .reveal || phase == .titleOut }

    /// The stage title is on screen during the intro.
    public var showsTitle: Bool { isIntro }

    public var isOutro: Bool {
        switch phase {
        case .outroDelay, .outroText, .outroHold, .outroFade, .panelIn, .panelHold, .finished: true
        default: false
        }
    }

    public var showsOutcomeText: Bool {
        switch phase {
        case .outroText, .outroHold, .outroFade, .panelIn, .panelHold, .finished: true
        default: false
        }
    }

    public var showsPanel: Bool { phase == .panelIn || phase == .panelHold || phase == .finished }

    public func duration(of phase: Phase) -> Int? {
        switch phase {
        case .card: durations.card
        case .reveal: durations.reveal
        case .titleOut: durations.titleOut
        case .outroDelay: durations.outroDelay
        case .outroText: durations.outroText
        case .outroHold: durations.outroHold
        case .outroFade: durations.outroFade
        case .panelIn: durations.panelIn
        case .panelHold: max(durations.panelHold, rewardTick + durations.panelSettle + 1)
        case .playing, .finished: nil
        }
    }

    /// 0…1 through the current timed phase (1 for untimed phases).
    public var progress: Double {
        guard let length = duration(of: phase), length > 0 else { return 1 }
        return min(1, Double(ticksInPhase) / Double(length))
    }

    /// Outro curtain progress: nil while the playfield is open, then the
    /// number of steps (0…`revealSteps`) the cover has advanced from the
    /// arena edges toward the centre; `revealSteps` once fully closed.
    public var coverStep: Int? {
        switch phase {
        case .outroFade: min(revealSteps, Int(progress * Double(revealSteps + 1)))
        case .panelIn, .panelHold, .finished: revealSteps
        default: nil
        }
    }

    /// The curtain is fully down: the results own the screen.
    public var isCovered: Bool { phase == .panelIn || phase == .panelHold || phase == .finished }

    /// Cells within this many strips of the arena centre are visible: nil
    /// while the card covers everything, `revealSteps` once fully open.
    public var revealStep: Int? {
        switch phase {
        case .card: nil
        case .reveal: min(revealSteps, Int(progress * Double(revealSteps + 1)))
        default: revealSteps
        }
    }

    /// Tick of `panelHold` at which the reward line appears (the total
    /// line's tick when there is no reward line).
    private var rewardTick: Int {
        (panelRows - 1) * max(1, durations.panelRowInterval) + (hasRewardLine ? durations.rewardDelay : 0)
    }

    /// The reward line is on screen: from its cue to the end of the panel.
    public var showsReward: Bool {
        guard hasRewardLine else { return false }
        switch phase {
        case .panelHold: return ticksInPhase > rewardTick
        case .finished: return true
        default: return false
        }
    }

    /// Results rows visible so far: row `k` appears with its `.panelRow(k)`
    /// cue (tick `k * panelRowInterval` of `panelHold`); all of them once
    /// the panel has settled.
    public var panelRowsVisible: Int {
        switch phase {
        case .panelHold where ticksInPhase > 0:
            min(panelRows, (ticksInPhase - 1) / max(1, durations.panelRowInterval) + 1)
        case .finished: panelRows
        default: 0
        }
    }

    /// One tick of the timeline. Returns the cues that fire on this tick.
    @discardableResult
    public mutating func advance() -> [Cue] {
        var cues: [Cue] = []
        if ticksInPhase == 0 {
            switch phase {
            case .card: cues.append(.cardTitle)
            case .reveal: cues.append(.reveal)
            case .outroText: cues.append(.outcomeText)
            case .outroFade: cues.append(.fade)
            case .panelHold: cues.append(.panelRow(0))
            default: break
            }
        } else if phase == .panelHold {
            if ticksInPhase % max(1, durations.panelRowInterval) == 0 {
                let row = ticksInPhase / max(1, durations.panelRowInterval)
                if row < panelRows { cues.append(.panelRow(row)) }
            }
            if hasRewardLine, ticksInPhase == rewardTick { cues.append(.reward) }
        }
        ticksInPhase += 1
        if let length = duration(of: phase), ticksInPhase >= length {
            phase = next(after: phase)
            ticksInPhase = 0
        }
        return cues
    }

    private func next(after phase: Phase) -> Phase {
        switch phase {
        case .card: .reveal
        case .reveal: .titleOut
        case .titleOut: .playing
        case .playing: .playing
        case .outroDelay: .outroText
        case .outroText: .outroHold
        case .outroHold: .outroFade
        case .outroFade: .panelIn
        case .panelIn: .panelHold
        case .panelHold: .finished
        case .finished: .finished
        }
    }

    /// The simulation decided the stage: start the outro. `resultRows` is
    /// the number of tally rows the results panel will list; the panel
    /// also shows a total line and, for a won stage with a clear bonus
    /// (`rewardLine`), the reward line after it; the hold stretches to fit
    /// them all. Ignored once an outcome is recorded (a decided stage
    /// stays decided).
    public mutating func beginOutro(won: Bool, resultRows: Int = 0, lossReason: String? = nil,
                                    rewardLine: Bool = false) {
        guard outcome == nil, phase == .playing else { return }
        outcome = won ? .won : .lost
        self.lossReason = won ? nil : lossReason
        hasRewardLine = won && rewardLine
        panelRows = max(0, resultRows) + 1
        phase = .outroDelay
        ticksInPhase = 0
    }

    /// A won stage moves on by itself when its timeline ends; a lost one
    /// keeps the panel up until the player restarts.
    public var wantsAutomaticContinue: Bool { phase == .finished && outcome == .won }
}

/// Enemies destroyed this stage — by archetype in first-kill order, and by
/// the reference's eight reward categories (ADR-0012) for the results
/// table: four rows of two categories, each row multiplied ×1…×4, and a
/// weighted total. Derived from events, never from GameCore state:
/// `remember` the pre-step world (archetypes of live enemies), then
/// `observe` the step's events.
public struct KillTally: Equatable, Sendable {
    public private(set) var byArchetype: [String: Int] = [:]
    public private(set) var order: [String] = []
    /// Kills per reward category 0…7.
    public private(set) var byCategory = [Int](repeating: 0, count: ScoreRules.rewardCategoryCount)
    private var archetypes: [Int: String] = [:]

    public init() {}

    /// The results table's fixed row count (reference layout).
    public static let tableRows = ScoreRules.rewardTableRows

    /// Kills in the two categories of table row `row` (0…3).
    public func rowCounts(_ row: Int) -> (left: Int, right: Int) {
        precondition(row >= 0 && row < Self.tableRows)
        return (byCategory[2 * row], byCategory[2 * row + 1])
    }

    /// Row `row`'s kills times its multiplier (`row + 1`).
    public func rowSubtotal(_ row: Int) -> Int {
        let counts = rowCounts(row)
        return (counts.left + counts.right) * (row + 1)
    }

    /// The reference's "总计": kills weighted by their row multiplier.
    public var weightedTotal: Int {
        (0..<Self.tableRows).reduce(0) { $0 + rowSubtotal($1) }
    }

    public mutating func remember(_ world: WorldState) {
        for tank in world.tanks where tank.ownerPlayerID == nil {
            archetypes[tank.entityID] = tank.archetypeID
        }
    }

    public mutating func observe(_ events: [DomainEvent]) {
        for case .tankDestroyed(let entityID, let owner, _) in events where owner == nil {
            guard let archetype = archetypes.removeValue(forKey: entityID) else { continue }
            byArchetype[archetype, default: 0] += 1
            if !order.contains(archetype) { order.append(archetype) }
            let category = EnemyArchetypes.attributes(for: archetype).rewardCategory
            if byCategory.indices.contains(category) { byCategory[category] += 1 }
        }
    }

    public var total: Int { byArchetype.values.reduce(0, +) }

    /// Rows in display order.
    public var rows: [(archetypeID: String, count: Int)] {
        order.map { ($0, byArchetype[$0] ?? 0) }
    }
}
