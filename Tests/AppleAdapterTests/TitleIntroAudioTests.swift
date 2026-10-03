import AVFoundation
import Testing
@testable import AppleAdapters

/// The launch sequence's sound is cut to the launch sequence (owner
/// 2026-10-03): nothing stops the tread cue, its own envelope recedes with
/// the exit run, so its length IS the coupling to the drive's timing.
@Suite struct TitleIntroAudioTests {
    /// Still rolling when the title comes out from under the tank; gone
    /// with the tank, not after it.
    @Test @MainActor func theTreadCueIsCutToTheDrive() throws {
        let url = try #require(GameAudio.soundURL(TitleScreen.treadCue), "the launch tread is not bundled")
        let player = try AVAudioPlayer(contentsOf: url)
        // 370 pt is the wordmark's measured width at its fixed 62 pt face;
        // it does not change with the device.
        let drive = TitleScreen.introTimeline(wordWidth: 370)
        #expect(player.duration > drive.crossing + 1.0, "the tread stops before the title is revealed")
        #expect(player.duration <= drive.total + 0.25, "the tread outlasts the drive")
        // Once per app start and five seconds long: one preloaded voice.
        #expect(GameAudio.poolSize(for: TitleScreen.treadCue) == 1)
    }
}
