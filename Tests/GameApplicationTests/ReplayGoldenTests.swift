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
    /// Regenerated 2026-09-04: checksum surface gained TankState.shieldHP
    /// (owner-directed shield resistance model). Movement behavior unchanged
    /// from the wall-facing regeneration earlier the same day.
    static let expectedChecksums: [UInt64] = [
        17583284604056582623,
        18260055849462118734,
        561997548960210401,
        9859516617248313513,
        2224897988836858112,
        5357791282718719940,
        13313955160955747045,
        12616633719743422206,
        8524789971571172086,
        9106615379872771189,
        10534414606633079956,
        5710980495297210003,
        6128235380038150655,
        28809721358555443,
        10221229875546441799,
        13237362225756583872,
        854694205370897411,
        1595406911242715709,
        14895657903944733730,
        8742550020181042875,
        2505124702762091975,
        4706214844332087070,
        7756826004472930666,
        5000091183190978182,
        3498766808486158130,
        11935128787726118832,
        8485643959421577430,
        4668294445692285056,
        2995929039876339876,
        15415659199873484909,
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
