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
    /// Generated 2026-09-03 from the initial M1 kernel; see file header.
    static let expectedChecksums: [UInt64] = [
        862832040561309351,
        11106629559503950514,
        6588413249945454481,
        18230100575597128545,
        9363824543355964882,
        4881531488233061390,
        5064253060051648223,
        14074433605275731248,
        12252734778789102058,
        817448448424918869,
        6462441219438151244,
        1432440965352688679,
        17682046516252251357,
        12690910833037253801,
        411323430050978565,
        6023541177075449850,
        6464550438227569785,
        14288995612899780461,
        6714963092344912326,
        3435872793433946399,
        1079694567536156873,
        15568014923502386607,
        11513244710909104696,
        15666858720424657593,
        10752671925702701057,
        8677925021911828132,
        10166290635889214635,
        6557344685005165802,
        18410126569936985017,
        553310731474566002,
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
