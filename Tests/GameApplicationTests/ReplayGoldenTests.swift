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
    /// Regenerated 2026-09-04: perpendicular turns with no junction within
    /// buffered travel now turn in place (owner-reported wall-facing rule);
    /// diverges from tick ~1260 where the script presses into a wall.
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
        10009029722083869479,
        11915497538133388478,
        491660377429001610,
        13360453837731950758,
        16017945969468479954,
        10348818979328173008,
        16762123468418820470,
        9551718003452074656,
        18411883314456497476,
        2318232783691235533,
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
