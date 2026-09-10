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
        5668269986311696585,
        11100556701688470720,
        17280348166696732739,
        17281319969935509867,
        12120924855084471946,
        1790670045228110430,
        558921934199204281,
        9087147459684298042,
        16919115778607916744,
        17147599900235775239,
        10507608599644819118,
        6346874872467267885,
        4726769161074256617,
        598545145388091085,
        1297414567329749713,
        7078062044781086538,
        2736099874078328925,
        17510131009610234863,
        1004799034346523172,
        12581458991700484661,
        7858390716014186065,
        2788312973125963664,
        16124508951822854156,
        3937182598834009240,
        2043568356382216692,
        13247686546510162362,
        13223891259454147112,
        11292669235816487434,
        12884807697727415230,
        6034940492331759839,
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
