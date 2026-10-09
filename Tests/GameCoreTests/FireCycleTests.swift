import Foundation
import Testing
@testable import GameCore

/// GAME_RULES R5.22 §9.2 (owner 2026-10-09: 把敌人的火力稍微降低一些, option
/// A): the fire cycles stretch with the difficulty. Enemy cooldowns are
/// shorter than their cycles, so a lined-up enemy fires once per cycle; the
/// cycle, not the window, sets sustained fire.
@Suite struct FireCycleTests {
    private func openTicks(_ profile: EnemyBehaviorProfile, rapid: Bool, over ticks: Int) -> (aligned: Int, breaking: Int) {
        var a = 0, b = 0
        for phase in 0..<ticks {
            let w = profile.fireWindows(phase: phase, rapid: rapid)
            if w.aligned { a += 1 }
            if w.breaking { b += 1 }
        }
        return (a, b)
    }

    @Test func atOneHundredTheWindowsAreTheAuthoredOnes() {
        let p = EnemyBehaviorProfile(fireWindowPercent: 100, fireCyclePercent: 100)
        #expect(openTicks(p, rapid: true, over: 32) == (16, 12))
        #expect(openTicks(p, rapid: false, over: 48).aligned == 12)
        // The window scale alone still trims the open part (R5.15).
        let narrow = EnemyBehaviorProfile(fireWindowPercent: 55, fireCyclePercent: 100)
        #expect(openTicks(narrow, rapid: false, over: 48).aligned == 6)
    }

    @Test func aStretchedCycleOpensLessOftenButKeepsItsShare() {
        // Standard: 48 → 62 ticks per cycle, open part 15 × 55 % = 8.
        let standard = EnemyBehaviorProfile(fireWindowPercent: 55, fireCyclePercent: 130)
        var openings = 0
        var wasOpen = false
        for phase in 0..<(62 * 10) {
            let open = standard.fireWindows(phase: phase, rapid: false).aligned
            if open && !wasOpen { openings += 1 }
            wasOpen = open
        }
        #expect(openings == 10)                                   // once per 62-tick cycle
        #expect(openTicks(standard, rapid: false, over: 62).aligned == 8)
        // Casual: rapid 32 → 51, normal 48 → 76, wall 64 → 102.
        let casual = EnemyBehaviorProfile(fireWindowPercent: 35, fireCyclePercent: 160)
        #expect(openTicks(casual, rapid: true, over: 51).aligned == 8)    // 25 × 35 % = 8
        #expect(openTicks(casual, rapid: false, over: 76).aligned == 6)   // 19 × 35 % = 6
    }

    @Test func profilesFromBeforeTheScaleReadAsOneHundred() throws {
        let json = #"{"decisionIntervalTicks":30,"baseFocusPercent":100,"wanderPercent":10,"fireWindowPercent":100,"courseCommitPercent":55}"#
        let p = try JSONDecoder().decode(EnemyBehaviorProfile.self, from: Data(json.utf8))
        #expect(p.fireCyclePercent == 100 && p == .standard)
        #expect(EnemyBehaviorProfile(fireCyclePercent: 40).validationIssues().contains { $0.contains("fire cycle") })
    }
}
