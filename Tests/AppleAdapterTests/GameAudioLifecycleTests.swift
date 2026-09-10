import Foundation
import Testing
import GameCore
@testable import AppleAdapters

/// A recording voice: what the mixer asked of it, without audio hardware.
private final class FakeVoice: AudioVoice {
    let name: String
    var isPlaying = false
    var volume: Float = 1
    var numberOfLoops = 0
    var currentTime: TimeInterval = 0
    var plays = 0
    var stops = 0
    var failsToPlay = false
    init(name: String) { self.name = name }
    func prepareToPlay() -> Bool { true }
    func play() -> Bool {
        guard !failsToPlay else { return false }
        isPlaying = true; plays += 1; return true
    }
    func stop() { isPlaying = false; stops += 1 }
}

private final class FakeBackend: AudioBackend, @unchecked Sendable {
    var voices: [FakeVoice] = []
    var failNextPlays = false
    /// Construction attempts, and which of them (1-based) fail with nil.
    var constructionAttempts = 0
    var failsConstruction: (Int) -> Bool = { _ in false }
    func activateSession() {}
    func makeVoice(named name: String) -> AudioVoice? {
        constructionAttempts += 1
        if failsConstruction(constructionAttempts) { return nil }
        let voice = FakeVoice(name: name)
        voice.failsToPlay = failNextPlays
        voices.append(voice)
        return voice
    }
    func playing(_ name: String) -> [FakeVoice] { voices.filter { $0.name == name && $0.isPlaying } }
    func plays(_ name: String) -> Int { voices.filter { $0.name == name }.reduce(0) { $0 + $1.plays } }
    func totalPlays(_ name: String) -> Int { voices.filter { $0.name == name }.reduce(0) { $0 + $1.plays } }
}

private let origin = Vec2i(x: 0, y: 0)

@MainActor
@Suite struct GameAudioLifecycleTests {
    private func makeAudio(clock: @escaping () -> TimeInterval = { 0 }) -> (GameAudio, FakeBackend) {
        let backend = FakeBackend()
        return (GameAudio(backend: backend, clock: clock), backend)
    }

    @Test func suspendStopsEverythingAndResumeRestartsOnlyWantedLoops() {
        let (audio, backend) = makeAudio()
        audio.play("sfx_fire_normal")
        audio.setLoop("sfx_flame_loop", active: true, volume: 0.4)
        #expect(backend.playing("sfx_fire_normal").count == 1)
        #expect(backend.playing("sfx_flame_loop").count == 1)
        audio.suspend()
        #expect(backend.playing("sfx_fire_normal").isEmpty)
        #expect(backend.playing("sfx_flame_loop").isEmpty)
        audio.play("sfx_hit_brick") // ignored while suspended
        #expect(backend.playing("sfx_hit_brick").isEmpty)
        audio.resume()
        #expect(backend.playing("sfx_flame_loop").count == 1) // wanted loop back
        #expect(backend.playing("sfx_fire_normal").isEmpty) // no historical one-shot
        #expect(backend.playing("sfx_hit_brick").isEmpty)
    }

    @Test func muteStopsRunningVoicesAndRefusesNewOnes() {
        let (audio, backend) = makeAudio()
        audio.play("sfx_fire_normal")
        audio.setLoop("sfx_flame_loop", active: true)
        audio.isEnabled = false
        #expect(backend.voices.allSatisfy { !$0.isPlaying })
        audio.play("sfx_fire_normal")
        audio.setLoop("sfx_flame_loop", active: true)
        #expect(backend.voices.allSatisfy { !$0.isPlaying })
        audio.isEnabled = true
        audio.play("sfx_fire_normal")
        #expect(backend.playing("sfx_fire_normal").count == 1)
    }

    @Test func loopVolumeUpdatesTheRunningVoice() {
        let (audio, backend) = makeAudio()
        audio.setLoop("sfx_flame_loop", active: true, volume: 0.3)
        audio.setLoop("sfx_flame_loop", active: true, volume: 0.8)
        let running = backend.playing("sfx_flame_loop")
        #expect(running.count == 1)
        #expect(running.first?.volume == 0.8)
        audio.setLoop("sfx_flame_loop", active: false)
        #expect(backend.playing("sfx_flame_loop").isEmpty)
    }

    @Test func dryFireIsThrottledOnAMonotonicClock() {
        var now: TimeInterval = 100
        let (audio, backend) = makeAudio(clock: { now })
        let click: [DomainEvent] = [.dryFire(entityID: 1, ownerPlayerID: .one, weaponID: "mine")]
        audio.play(events: click)
        now += 0.1
        audio.play(events: click) // too soon
        #expect(backend.totalPlays("sfx_dry_fire") == 1)
        now += 0.3
        audio.play(events: click)
        #expect(backend.totalPlays("sfx_dry_fire") == 2)
        audio.resetForNewWorld()
        audio.play(events: click) // fresh world, fresh throttle
        #expect(backend.totalPlays("sfx_dry_fire") == 3)
    }

    @Test func baseDamageHasPriorityOverLaunchVoicesInTheSameBatch() {
        let batch: [DomainEvent] = [
            .weaponFired(entityID: 1, ownerPlayerID: .one, weaponID: "normal", channel: .normal,
                         position: origin, facing: .up),
            .weaponFired(entityID: 2, ownerPlayerID: nil, weaponID: "ap", channel: .special,
                         position: origin, facing: .up),
            .baseDamaged(damage: 1, remaining: 2, allied: false),
        ]
        let names = GameAudio.soundNames(for: batch)
        #expect(names.contains("sfx_base_hit"))
        #expect(!names.contains("sfx_fire_normal") && !names.contains("sfx_fire_ap"))
    }

    @Test func alliedBaseHitHasItsOwnVoiceEvenOnTheKillingBlow() {
        let allied = GameAudio.soundNames(for: [.baseDamaged(damage: 1, remaining: 2, allied: true)])
        #expect(allied == ["sfx_base_own_hit"])
        let lethal = GameAudio.soundNames(for: [
            .baseDamaged(damage: 1, remaining: 0, allied: true),
            .stageLost(reason: "base_destroyed"),
        ])
        #expect(lethal.contains("sfx_base_own_hit") && lethal.contains("sfx_base_destroyed"))
        #expect(!lethal.contains("sfx_base_hit"))
        #expect(GameHaptics.cues(for: [.baseDamaged(damage: 1, remaining: 2, allied: true)]) == [.error])
        #expect(GameHaptics.cues(for: [.baseDamaged(damage: 1, remaining: 2, allied: false)]) == [.warning, .heavy])
    }

    /// R4-06: a dry-fire request ignored while suspended/muted must not
    /// throttle the first real one after resume.
    @Test func ignoredDryFireDoesNotCommitTheThrottle() {
        var now: TimeInterval = 0
        let (audio, backend) = makeAudio(clock: { now })
        let click: [DomainEvent] = [.dryFire(entityID: 1, ownerPlayerID: .one, weaponID: "mine")]
        audio.suspend()
        audio.play(events: click)
        now = 0.1
        audio.resume()
        audio.play(events: click)
        #expect(backend.totalPlays("sfx_dry_fire") == 1)
    }

    /// R4-06: a wanted loop whose voice the platform stopped is restarted;
    /// a failed start is retried with backoff, not per frame.
    @Test func wantedLoopIsReconciledAgainstActualPlayback() {
        var now: TimeInterval = 10
        let (audio, backend) = makeAudio(clock: { now })
        audio.setLoop("sfx_flame_loop", active: true)
        let first = backend.playing("sfx_flame_loop").first
        first?.isPlaying = false // interrupted externally
        audio.setLoop("sfx_flame_loop", active: true)
        #expect(backend.playing("sfx_flame_loop").count == 1)
        #expect(backend.playing("sfx_flame_loop").first !== first)

        backend.failNextPlays = true
        audio.setLoop("sfx_flame_loop", active: false)
        let before = backend.voices.count
        audio.setLoop("sfx_flame_loop", active: true) // start fails
        audio.setLoop("sfx_flame_loop", active: true) // same second: no retry
        audio.setLoop("sfx_flame_loop", active: true)
        #expect(backend.voices.count == before + 1)
        backend.failNextPlays = false
        now += 1.1
        audio.setLoop("sfx_flame_loop", active: true) // backoff elapsed: retried
        #expect(backend.playing("sfx_flame_loop").count == 1)
    }

    @Test func newWorldStopsOneShotsAsWellAsLoops() {
        let (audio, backend) = makeAudio()
        audio.play(events: [.stageLost(reason: "base_destroyed")])
        #expect(!backend.playing("sfx_base_destroyed").isEmpty)
        audio.resetForNewWorld()
        #expect(backend.voices.allSatisfy { !$0.isPlaying })
    }
}

/// Rapid fire: launch voices are pre-warmed and a busy pool drops the
/// request instead of seeking-and-restarting a playing voice on the main
/// thread (the stutter the owner reported while firing rapid rounds).
@MainActor
@Suite struct RapidFireAudioTests {
    @Test func poolsArePreWarmedAtConstruction() {
        let backend = FakeBackend()
        _ = GameAudio(backend: backend, clock: { 0 })
        let expected = GameAudio.allSounds.reduce(0) { $0 + GameAudio.poolSize(for: $1) }
        #expect(backend.voices.count == expected)
        #expect(backend.voices.filter { $0.name == "sfx_fire_rapid" }.count == 6)
        #expect(backend.voices.filter { $0.name == "sfx_fire_normal" }.count == 3)
    }

    @Test func aBusyPoolDropsTheRequestInsteadOfRestartingAVoice() {
        let backend = FakeBackend()
        let audio = GameAudio(backend: backend, clock: { 0 })
        for _ in 0..<3 { #expect(audio.play("sfx_fire_normal")) }
        #expect(backend.playing("sfx_fire_normal").count == 3)
        let before = backend.plays("sfx_fire_normal")
        #expect(!audio.play("sfx_fire_normal")) // dropped
        #expect(backend.plays("sfx_fire_normal") == before)
        #expect(backend.voices.filter { $0.name == "sfx_fire_normal" }.count == 3) // no fourth voice
        backend.playing("sfx_fire_normal")[0].stop()
        #expect(audio.play("sfx_fire_normal")) // a freed voice serves the next shot
    }

    /// Rapid fire at 83 ms with a 340 ms clip overlaps up to five launches;
    /// six voices keep every launch audible without hot-path allocation.
    @Test func rapidFireHasEnoughVoicesForItsCadence() {
        let backend = FakeBackend()
        let audio = GameAudio(backend: backend, clock: { 0 })
        for _ in 0..<6 { #expect(audio.play("sfx_fire_rapid")) }
        #expect(!audio.play("sfx_fire_rapid")) // seventh overlapping launch dropped
        #expect(backend.voices.filter { $0.name == "sfx_fire_rapid" }.count == 6)
    }

    /// R18-01: a pool that came up short at construction never allocates
    /// during playback either — it drops like a full one.
    @Test func aPartiallyWarmedPoolNeverAllocatesDuringPlayback() {
        let backend = FakeBackend()
        backend.failsConstruction = { $0 % 3 == 0 } // a three-voice pool ends up with two
        let audio = GameAudio(backend: backend, clock: { 0 })
        let attemptsAfterInit = backend.constructionAttempts
        #expect(backend.voices.filter { $0.name == "sfx_fire_normal" }.count == 2)
        #expect(audio.play("sfx_fire_normal") && audio.play("sfx_fire_normal"))
        #expect(!audio.play("sfx_fire_normal")) // both busy: dropped, not constructed
        #expect(backend.constructionAttempts == attemptsAfterInit)
        #expect(backend.voices.filter { $0.name == "sfx_fire_normal" }.count == 2)
    }
}

/// R4-04: the controller is a complete inactive-state barrier.
@MainActor
@Suite struct ControllerLifecycleTests {
    private func makeController() -> (MovementLabController, FakeBackend) {
        let backend = FakeBackend()
        let world = WorldState(terrain: TerrainGrid(arena: .universal), seed: 1)
        let controller = MovementLabController(world: world, audio: GameAudio(backend: backend))
        return (controller, backend)
    }

    @Test func suspendBeforeFirstStartStillSuspendsServicesAndInput() {
        let (controller, backend) = makeController()
        controller.suspend()
        #expect(controller.audio.isSuspended)
        #expect(controller.haptics.isSuspended)
        controller.audio.setLoop("sfx_flame_loop", active: true)
        #expect(backend.playing("sfx_flame_loop").isEmpty)
        controller.input.pressSpecialFire(from: .touch)
        #expect(!controller.input.specialFireHeld) // refused while inactive
        controller.start()
        #expect(!controller.audio.isSuspended && !controller.haptics.isSuspended)
        #expect(backend.playing("sfx_flame_loop").count == 1) // wanted loop resumed
        controller.input.pressSpecialFire(from: .touch)
        #expect(controller.input.specialFireHeld)
    }

    @Test func pressesDuringSuspensionDoNotSurviveResume() {
        let (controller, _) = makeController()
        controller.start()
        controller.suspend()
        controller.input.pressSpecialFire(from: .touch)
        controller.input.press(.up, from: .key("W"))
        controller.start()
        #expect(!controller.input.specialFireHeld)
        #expect(controller.input.held == nil)
    }

    /// R5-02: a controller is inactive from construction — the initial
    /// inactive view path needs no explicit suspend call.
    @Test func controllerStartsInactiveUntilStarted() {
        let (controller, backend) = makeController()
        #expect(controller.audio.isSuspended && controller.haptics.isSuspended)
        controller.input.pressSpecialFire(from: .touch)
        #expect(!controller.input.specialFireHeld)
        controller.audio.setLoop("sfx_flame_loop", active: true)
        #expect(backend.playing("sfx_flame_loop").isEmpty)
        controller.start()
        #expect(!controller.audio.isSuspended && !controller.haptics.isSuspended)
        #expect(backend.playing("sfx_flame_loop").count == 1)
        controller.input.pressSpecialFire(from: .touch)
        #expect(controller.input.specialFireHeld)
    }

    /// R5-02: a physical callback OBSERVED while inactive but delivered after
    /// resume is dropped — admission is decided by when the event happened.
    @Test func callbackObservedWhileInactiveIsDroppedAfterResume() async {
        let (controller, _) = makeController()
        let generations = DeviceGenerations()
        controller.start()
        controller.suspend()
        PhysicalBindings.deliver(to: controller.input, device: "pad", generations: generations) {
            $0.pressSpecialFire(from: .controller("pad", control: "buttonB"))
        }
        controller.start() // before the queued delivery runs
        for _ in 0..<20 { await Task.yield() }
        #expect(!controller.input.specialFireHeld)
        // A callback observed after the resume is admitted.
        PhysicalBindings.deliver(to: controller.input, device: "pad", generations: generations) {
            $0.pressSpecialFire(from: .controller("pad", control: "buttonB"))
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.input.specialFireHeld)
    }
}
