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
    /// Regenerated 2026-09-03 with M3: checksum surface extended to
    /// pickups/telegraphs/stage and player respawn-retention fields. Same
    /// input script; movement behavior unchanged.
    static let expectedChecksums: [UInt64] = [
        8260975046611885119,
        5014849822761385582,
        13351190130749749313,
        1280905171417905929,
        5951493913301446944,
        3924634179889187044,
        16752504585474776901,
        3774809122203394846,
        4069756949456987158,
        998631645211471061,
        9303869239473430964,
        13197007094806260595,
        17408636909857534303,
        6610767950945654035,
        133325134366010279,
        13950313845950529248,
        11251278314248288483,
        17944007131741629981,
        11734796581883049922,
        7460740919157276571,
        9061529408994678041,
        3062689661668849333,
        1643355299093154886,
        14748872409205058049,
        15909826365691057949,
        7113856313919682351,
        5227793739940515037,
        14955763905154225724,
        8663381327235187083,
        11319265526741265975,
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

    @Test func replayReproducesTheRecording() {
        let recording = recordRun()
        let replayed = ReplayPlayer.replay(recording, ticks: M1MovementGolden.tickCount)
        #expect(replayed == recording.checksums)
    }
}
