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
    /// Regenerated 2026-09-15 a third time (GAME_RULES R5.2, ADR-0019): the
    /// owner's second device run halved the speeds again (base 1 966 080
    /// mSU/s, 40 % of R5), so the same drive covers less ground.
    /// Regenerated 2026-09-15 again (GAME_RULES R5.1, ADR-0019): the owner's
    /// first device run slowed every tank 20 % (base 3 932 160 mSU/s), so the
    /// same drive reaches the fixture's walls and ice at other ticks.
    /// Regenerated 2026-09-15 (GAME_RULES R5, ADR-0018): the player base speed
    /// became 4 915 200 mSU/s (4.8 cells/s, was 2880 su/s), so the drive
    /// covers more ground and meets the fixture's walls and ice at other
    /// ticks; the checksum surface also changed with R5 state (layered
    /// terrain cells, fire-input fields, statistics, fort records). The
    /// fixture file itself is unchanged.
    /// Regenerated 2026-09-10 (ADR-0016, M4 item 5): the lab fixture's ice
    /// patch (cells x 4–8, y 21–24) now SLIDES the tank — this script drives
    /// down through it and turns right at tick 240, which converts the
    /// remaining momentum into a 1.5-cell slide before the turn takes the
    /// tank on; the checksum surface also gained TankState.landingSubunits
    /// (nil here) and the rulesets' ice/slow/launch tunables. Movement off
    /// the ice is unchanged; the first checksums that move are the ones
    /// after the turn.
    /// Regenerated 2026-09-09 (joint review, batch 1): checksum surface
    /// gained BaseState.fortRingRestore / burnCooldownTicks (the lab fixture
    /// carries a base) plus ProjectileState.hitTankIDs and
    /// FireHazardState.ownerEntityID (absent from this movement-only run).
    /// No projectile is ever fired here and movement code is untouched, so
    /// only the checksum surface moved. Previous regeneration 2026-09-08
    /// (reference drop channels).
    static let expectedChecksums: [UInt64] = [
        14041283426453554439,
        12428072425985180926,
        1778078765131903001,
        12308548702423970880,
        4713283805041046024,
        13766850761942782425,
        10563797720925675971,
        3850655303086955996,
        546626122760507124,
        9927228405540420466,
        12781310917986289940,
        15543088467148412809,
        6417909684869948170,
        5854895671980600305,
        13828121401692897971,
        3986946857996999924,
        8728507583582782760,
        348543546275534920,
        13378349270945241861,
        14872617173581075138,
        11937409454119970741,
        1274886545580287596,
        7223086889776497304,
        5610045536128905764,
        14918223497653497616,
        11233773381777437112,
        17702738827908095680,
        8995365854016485327,
        11804902164246645383,
        1235481955612392949,
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
