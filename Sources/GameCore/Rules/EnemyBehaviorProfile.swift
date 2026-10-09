/// Difficulty-shaped enemy behaviour (GAME_RULES §9.2; ADR-0015).
/// Ruleset DATA carried by the stage (`StageState.enemyBehavior`) so the
/// world is self-describing: replays and snapshots need no side channel,
/// and the AI never branches on a difficulty identity. `.standard` is the
/// behaviour the enemy brain had before profiles existed.
public struct EnemyBehaviorProfile: Codable, Equatable, Sendable {
    /// Movement decisions every this many ticks (reaction interval).
    public var decisionIntervalTicks: Int
    /// Percent scale on each archetype's base-focus roll (100 = authored).
    public var baseFocusPercent: Int
    /// Percent of decisions that wander instead of homing (§10.4).
    public var wanderPercent: Int
    /// Percent scale on the open part of the aligned-fire duty cycle
    /// (100 = authored windows; more = more shots when aligned).
    public var fireWindowPercent: Int
    /// Percent chance a moving enemy keeps its course past a decision
    /// (course commitment; lower = more reactive).
    public var courseCommitPercent: Int
    /// R5.22 (owner 2026-10-09): percent scale on the fire CYCLES (32 / 48 /
    /// 64 ticks) and their open parts together. Enemy cooldowns are shorter
    /// than their cycles (explosive LV0's 50 against 48 aside), so a lined-up
    /// enemy fires once per cycle
    /// whatever the window — this, not `fireWindowPercent`, sets sustained
    /// fire. 100 = authored; 150 = a third fewer shots.
    public var fireCyclePercent: Int

    public init(decisionIntervalTicks: Int = 30, baseFocusPercent: Int = 100, wanderPercent: Int = 10,
                fireWindowPercent: Int = 100, courseCommitPercent: Int = 55, fireCyclePercent: Int = 100) {
        self.decisionIntervalTicks = decisionIntervalTicks
        self.baseFocusPercent = baseFocusPercent
        self.wanderPercent = wanderPercent
        self.fireWindowPercent = fireWindowPercent
        self.courseCommitPercent = courseCommitPercent
        self.fireCyclePercent = fireCyclePercent
    }

    private enum CodingKeys: String, CodingKey {
        case decisionIntervalTicks, baseFocusPercent, wanderPercent, fireWindowPercent, courseCommitPercent,
             fireCyclePercent
    }

    /// `fireCyclePercent` absent (difficulty files and snapshots from before
    /// R5.22) reads as 100.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decisionIntervalTicks = try c.decode(Int.self, forKey: .decisionIntervalTicks)
        baseFocusPercent = try c.decode(Int.self, forKey: .baseFocusPercent)
        wanderPercent = try c.decode(Int.self, forKey: .wanderPercent)
        fireWindowPercent = try c.decode(Int.self, forKey: .fireWindowPercent)
        courseCommitPercent = try c.decode(Int.self, forKey: .courseCommitPercent)
        fireCyclePercent = try c.decodeIfPresent(Int.self, forKey: .fireCyclePercent) ?? 100
    }

    /// The aligned-fire and wall-breaking windows at `phase` (GAME_RULES
    /// §9.2): rapid 16 of 32 ticks, other families 12 of 48, wall breaking
    /// 12 of 64; every cycle and its open part stretched by
    /// `fireCyclePercent`, the open part then scaled by `fireWindowPercent`.
    public func fireWindows(phase: Int, rapid: Bool) -> (aligned: Bool, breaking: Bool) {
        func stretched(_ ticks: Int) -> Int { max(1, ticks * fireCyclePercent / 100) }
        func open(_ base: Int, of period: Int) -> Bool {
            let cycle = stretched(period)
            return phase % cycle < min(cycle, stretched(base) * fireWindowPercent / 100)
        }
        return (rapid ? open(16, of: 32) : open(12, of: 48), open(12, of: 64))
    }

    public static let standard = EnemyBehaviorProfile()

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if !(1...600).contains(decisionIntervalTicks) { issues.append("decision interval \(decisionIntervalTicks) outside 1…600") }
        if !(0...300).contains(baseFocusPercent) { issues.append("base focus percent \(baseFocusPercent) outside 0…300") }
        if !(0...100).contains(wanderPercent) { issues.append("wander percent \(wanderPercent) outside 0…100") }
        if !(0...400).contains(fireWindowPercent) { issues.append("fire window percent \(fireWindowPercent) outside 0…400") }
        if !(0...100).contains(courseCommitPercent) { issues.append("course commit percent \(courseCommitPercent) outside 0…100") }
        if !(50...400).contains(fireCyclePercent) { issues.append("fire cycle percent \(fireCyclePercent) outside 50…400") }
        return issues
    }
}

/// An authored director phase (plan §10.2 "elite timing", §11.3 VS-03
/// "elite wave … base shield/repair opportunity before final pressure",
/// §6.6 base repair as a stage-authored director effect): once the stage
/// has scheduled `afterSpawned` enemies, the reinforcements are pushed to
/// the FRONT of the spawn queue, the alive cap may change, and the base
/// may be repaired to full durability. Phases apply in order, once each.
public struct DirectorPhase: Codable, Equatable, Sendable {
    public var id: String
    public var afterSpawned: Int
    public var reinforcements: [String]
    public var maxAliveEnemies: Int?
    public var repairsBase: Bool

    public init(id: String, afterSpawned: Int, reinforcements: [String] = [],
                maxAliveEnemies: Int? = nil, repairsBase: Bool = false) {
        self.id = id
        self.afterSpawned = afterSpawned
        self.reinforcements = reinforcements
        self.maxAliveEnemies = maxAliveEnemies
        self.repairsBase = repairsBase
    }
}
