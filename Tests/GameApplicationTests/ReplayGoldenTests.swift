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
    /// Regenerated 2026-09-03 with M2 combat: the lab fixture gained enemy
    /// dummies and the base, and the checksum surface extended to combat
    /// entities. Same input script; movement behavior unchanged.
    static let expectedChecksums: [UInt64] = [
        930431710757989395,
        13750484399870368730,
        2125806196128089653,
        17756080705229939717,
        6747431703436410202,
        11827039391831936654,
        17428350695162817847,
        8181642052989840260,
        4130134808684172978,
        11385239105255920225,
        266927319778217672,
        3947462152294129471,
        770918178687934089,
        10320916225450764493,
        14378418744159642865,
        14316150572403745490,
        1930312051729717885,
        12765788471390004377,
        370156844351426982,
        13239590785186928535,
        4031519224237061485,
        15708687104576461127,
        12559315068886543308,
        12743071518806359595,
        6496701372275769847,
        11090746055291202027,
        15029998164784095257,
        8131346877794753616,
        17360689571839141991,
        17218182675585747521,
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
