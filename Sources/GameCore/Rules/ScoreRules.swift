/// Stage-clear score bonuses recovered from the reference's results screens
/// (30 screens of the owner's gameplay recording, measured 2026-09-10;
/// ADR-0012, proposed). Two bonuses land in the score when a stage is won:
/// the TALLY bonus counts into the score while the results table fills and
/// the REWARD bonus follows it ("Reward +N"). Both are constant within a
/// bracket of stages and grow at stages 11 and 26 — the recording's two
/// continues coincide with those brackets, so a "bonus grows with continues"
/// reading cannot be excluded; the bracket reading is the recorded default.
/// The bonuses are stage data (`StageState.clearBonus`, set by content from
/// the stage number) so the kernel needs no stage-number concept.
public struct ScoreRules: Equatable, Sendable {
    public struct ClearBonus: Codable, Equatable, Sendable {
        public var tally: Int
        public var reward: Int
        public init(tally: Int, reward: Int) {
            self.tally = tally
            self.reward = reward
        }
        public static let none = ClearBonus(tally: 0, reward: 0)
        public var total: Int { tally + reward }
    }

    public struct Tier: Equatable, Sendable {
        /// First stage number (1-based) the tier applies to.
        public var firstStage: Int
        public var bonus: ClearBonus
        public init(firstStage: Int, bonus: ClearBonus) {
            self.firstStage = firstStage
            self.bonus = bonus
        }
    }

    /// Ascending by `firstStage`; a stage takes the last tier at or below it.
    public var clearTiers: [Tier]

    public init(clearTiers: [Tier]) {
        self.clearTiers = clearTiers.sorted { $0.firstStage < $1.firstStage }
    }

    /// The clear bonus of a stage number; `.none` below the first tier
    /// (stage numbers start at 1) or with no tiers.
    public func clearBonus(stageNumber: Int) -> ClearBonus {
        var chosen = ClearBonus.none
        for tier in clearTiers where tier.firstStage <= stageNumber { chosen = tier.bonus }
        return chosen
    }

    /// Reference values: stages 1–10 (200 / 330), 11–25 (600 / 660),
    /// 26 and later (1000 / 1000).
    public static let reference = ScoreRules(clearTiers: [
        Tier(firstStage: 1, bonus: ClearBonus(tally: 200, reward: 330)),
        Tier(firstStage: 11, bonus: ClearBonus(tally: 600, reward: 660)),
        Tier(firstStage: 26, bonus: ClearBonus(tally: 1000, reward: 1000)),
    ])

    /// The reference's results table lists kills in eight reward categories
    /// (GAME_MECHANICS_SPEC §8.2, last column) as four rows of two: row `r`
    /// holds categories `2r` and `2r+1` and multiplies their kills by `r+1`.
    public static let rewardCategoryCount = 8
    public static let rewardTableRows = 4

    public static func rewardMultiplier(category: Int) -> Int {
        precondition(category >= 0 && category < rewardCategoryCount, "reward category out of range")
        return category / 2 + 1
    }
}
