/// Difficulty-shaped enemy behaviour (plan §10.7: targeted behaviour, base
/// focus, reaction interval, telegraph duration, composition; ADR-0015).
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
    /// Percent chance per mine-laying beat that a mine layer drops a mine
    /// (reference 20 %, §9.1).
    public var minePlacePercent: Int
    /// Percent chance a moving enemy keeps its course past a decision
    /// (course commitment; lower = more reactive).
    public var courseCommitPercent: Int

    public init(decisionIntervalTicks: Int = 30, baseFocusPercent: Int = 100, wanderPercent: Int = 10,
                fireWindowPercent: Int = 100, minePlacePercent: Int = 20, courseCommitPercent: Int = 55) {
        self.decisionIntervalTicks = decisionIntervalTicks
        self.baseFocusPercent = baseFocusPercent
        self.wanderPercent = wanderPercent
        self.fireWindowPercent = fireWindowPercent
        self.minePlacePercent = minePlacePercent
        self.courseCommitPercent = courseCommitPercent
    }

    public static let standard = EnemyBehaviorProfile()

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if !(1...600).contains(decisionIntervalTicks) { issues.append("decision interval \(decisionIntervalTicks) outside 1…600") }
        if !(0...300).contains(baseFocusPercent) { issues.append("base focus percent \(baseFocusPercent) outside 0…300") }
        if !(0...100).contains(wanderPercent) { issues.append("wander percent \(wanderPercent) outside 0…100") }
        if !(0...400).contains(fireWindowPercent) { issues.append("fire window percent \(fireWindowPercent) outside 0…400") }
        if !(0...100).contains(minePlacePercent) { issues.append("mine place percent \(minePlacePercent) outside 0…100") }
        if !(0...100).contains(courseCommitPercent) { issues.append("course commit percent \(courseCommitPercent) outside 0…100") }
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
