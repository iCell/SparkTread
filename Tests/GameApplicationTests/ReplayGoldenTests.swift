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
    /// Regenerated 2026-09-03 for the 56×27 universal arena (ADR-0009);
    /// previous values covered the provisional 48×27 fixture.
    static let expectedChecksums: [UInt64] = [
        9082519820445521807,
        17775660797242842154,
        10292925488974365001,
        11787158773327934617,
        16828638170928367018,
        16797375433671237846,
        15563799541270632903,
        9643354863503030360,
        3995727263746611058,
        14671117256757642893,
        11097130099691452548,
        7944744193839779007,
        4756822108631356549,
        15721962540978954769,
        16978226977018747229,
        943482658629622866,
        8790981026288924673,
        215338708648050325,
        12012560187063207582,
        17430909843261272679,
        18171984048345033329,
        13530070364688539479,
        185180716701942480,
        16916067252482420577,
        2284994907473062937,
        1734323522388856876,
        4865938772222349363,
        5454599811319443442,
        13931648505890058977,
        3532596647917134954,
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
