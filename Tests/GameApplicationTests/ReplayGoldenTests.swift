import Testing
import GameCore
@testable import GameApplication

/// The M1 movement replay golden (§18.1): a known input stream over the
/// Movement Lab fixture with expected periodic checksums. A gameplay-rule
/// change that alters these values must intentionally regenerate them WITH A
/// REVIEW NOTE — never update the constants to silence a failure.
enum M1MovementGolden {
    /// Deterministic 1,800-tick (30 s) drive around the lab fixture.
    static func direction(forTick tick: Int) -> Direction? {
        switch tick {
        case 0..<240: .down
        case 240..<300: .right
        case 300..<540: .down
        case 540..<900: .right
        case 900..<960: nil
        case 960..<1200: .up
        case 1200..<1500: .right
        case 1500..<1560: .left
        default: .down
        }
    }

    static let tickCount = 1800

    /// Expected checksums at tick 60, 120, …, 1800.
    /// Regenerated 2026-09-09 (joint review, batch 1): checksum surface
    /// gained BaseState.fortRingRestore / burnCooldownTicks (the lab fixture
    /// carries a base) plus ProjectileState.hitTankIDs and
    /// FireHazardState.ownerEntityID (absent from this movement-only run).
    /// No projectile is ever fired here and movement code is untouched, so
    /// only the checksum surface moved. Previous regeneration 2026-09-08
    /// (reference drop channels).
    static let expectedChecksums: [UInt64] = [
        6508903943244204425,
        16864347844189187712,
        13210481412500585027,
        3860192783540104939,
        7638081656561312586,
        10799961910510879262,
        13150152850379409975,
        4664461216949394160,
        13889321090074331720,
        7837395418827238279,
        7161482697113056814,
        9468835705284178733,
        6538002491864687913,
        11917242649273594829,
        10704438917131669777,
        11239148211524507146,
        4905692039835354525,
        17541632555893126447,
        16952540740029952228,
        9121229674845828085,
        17558946178542102673,
        1674773680863539984,
        5401361521211181068,
        14164405916821171800,
        16375042646932094196,
        9781398832051472826,
        2483302849247394088,
        8010083759241252042,
        14528596449182028030,
        18240655918099470687,
    ]
}

@Suite struct ReplayGoldenTests {
    private func recordRun() -> ReplayRecording {
        var session = MovementLabSession()
        for tick in 0..<M1MovementGolden.tickCount {
            session.advance(holding: M1MovementGolden.direction(forTick: tick))
        }
        return session.recording
    }

    @Test func movementGoldenChecksumsMatch() {
        let recording = recordRun()
        #expect(recording.checksums.map(\.checksum) == M1MovementGolden.expectedChecksums)
    }

    @Test func replayReproducesTheRecording() throws {
        let recording = recordRun()
        let replayed = try ReplayPlayer.replay(recording, ticks: M1MovementGolden.tickCount)
        #expect(replayed == recording.checksums)
    }
}
