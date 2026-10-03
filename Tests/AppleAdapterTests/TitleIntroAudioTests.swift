import AVFoundation
import GameCore
import Testing
@testable import AppleAdapters

/// The launch sequence's sounds are cut to the launch sequence (owner
/// 2026-10-03): nothing stops the tread cue, its own envelope recedes with
/// the exit run, so its length IS the coupling to the drive's timing; and
/// the two shots fall while the tank is still over the title, at the
/// game's own gun cadence.
@Suite struct TitleIntroAudioTests {
    /// 370 pt is the wordmark's measured width at its fixed 62 pt face; it
    /// does not change with the device.
    private let wordWidth: CGFloat = 370

    /// Still rolling when the title comes out from under the tank; gone
    /// with the tank, not after it.
    @Test @MainActor func theTreadCueIsCutToTheDrive() throws {
        let url = try #require(GameAudio.soundURL(TitleScreen.treadCue), "the launch tread is not bundled")
        let player = try AVAudioPlayer(contentsOf: url)
        let drive = TitleScreen.introTimeline(wordWidth: wordWidth)
        #expect(player.duration > drive.crossing + 1.0, "the tread stops before the title is revealed")
        #expect(player.duration <= drive.total + 0.25, "the tread outlasts the drive")
        // Once per app start and five seconds long: one preloaded voice.
        #expect(GameAudio.poolSize(for: TitleScreen.treadCue) == 1)
    }

    /// Two shots, both while the tank is over the word, the second at the
    /// normal gun's LV1 cooldown after the first — the title's tank shoots
    /// like the one the player is about to drive — with the normal shot's
    /// own voice, which must be bundled.
    @Test @MainActor func theTwoShotsFallOverTheTitleAtTheGunsOwnCadence() throws {
        let drive = TitleScreen.introTimeline(wordWidth: wordWidth)
        #expect(drive.shots.count == 2)
        #expect(drive.shots.allSatisfy { $0 > 0 && $0 < drive.crossing }, "\(drive.shots) vs crossing \(drive.crossing)")
        let gun = try #require(WeaponRuleset.provisional.weapon("normal"))
        let cadence = Double(gun.cooldownTicks[0]) / Double(MovementRuleset.ticksPerSecond)
        #expect(abs((drive.shots[1] - drive.shots[0]) - cadence) < 0.001)
        #expect(GameAudio.soundURL(TitleScreen.shotCue) != nil, "the shot voice is not bundled")
        // The shells outrun the tank by the game's own ratio, so they visibly
        // leave it rather than ride along.
        #expect(TitleScreen.shellSpeedRatio > 2)
    }
}
