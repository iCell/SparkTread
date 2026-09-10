import AVFoundation
import Testing
import GameCore
@testable import AppleAdapters

private let origin = Vec2i(x: 0, y: 0)

@Suite struct GameAudioTests {
    /// Every mapped sound ships in the resource bundle and decodes.
    @Test func allGeneratedSoundsLoadFromTheBundle() throws {
        for name in GameAudio.allSounds {
            let url = try #require(GameAudio.soundURL(name), "missing \(name).wav")
            let player = try AVAudioPlayer(contentsOf: url)
            #expect(player.duration > 0.02, "\(name) is empty")
        }
    }

    @Test func eventMappingCoversCoreMoments() {
        func names(_ events: [DomainEvent]) -> [String] { GameAudio.soundNames(for: events) }
        #expect(names([.weaponFired(entityID: 1, ownerPlayerID: .one, weaponID: "normal", channel: .normal,
                                    position: origin, facing: .up)]) == ["sfx_fire_normal"])
        // Owner identity travels with the event: no cached player id needed.
        #expect(names([.tankDestroyed(entityID: 7, ownerPlayerID: .one, position: origin)])
                == ["sfx_player_explode"])
        #expect(names([.tankDestroyed(entityID: 9, ownerPlayerID: nil, position: origin)])
                == ["sfx_tank_explode"])
        // Structured impacts replace inference: a brick notch is one crunch
        // however many cells changed; the border is steel; a cancelled or
        // deflected shot ticks; an expiry is silent.
        let brick = names([
            .projectileDestroyed(entityID: 3, weaponID: "normal", position: origin, impact: .brick),
            .terrainChanged(cellX: 1, cellY: 1, quadrantMask: 0),
            .terrainChanged(cellX: 1, cellY: 2, quadrantMask: 0),
        ])
        #expect(brick == ["sfx_hit_brick"])
        #expect(names([.projectileDestroyed(entityID: 3, weaponID: "normal", position: origin, impact: .boundary)])
                == ["sfx_hit_steel"])
        #expect(names([.projectileHit(entityID: 3, weaponID: "ap", position: origin, impact: .steel)])
                == ["sfx_hit_steel"])
        #expect(names([.projectileDestroyed(entityID: 3, weaponID: "normal", position: origin, impact: .projectile)])
                == ["sfx_deflect"])
        #expect(names([.projectileDestroyed(entityID: 3, weaponID: "normal", position: origin, impact: .expired)])
                .isEmpty)
        // Dry fire is a player-only cue (§12.4): AI mine layers stay silent.
        #expect(names([.dryFire(entityID: 9, ownerPlayerID: nil, weaponID: "mine")]).isEmpty)
        #expect(names([.dryFire(entityID: 7, ownerPlayerID: .one, weaponID: "mine")]) == ["sfx_dry_fire"])
        // Base loss plays the collapse and the stinger, not the hit alarm.
        let loss = names([
            .baseDamaged(damage: 1, remaining: 0, allied: false),
            .stageLost(reason: "base_destroyed"),
        ])
        #expect(loss.contains("sfx_base_destroyed"))
        #expect(!loss.contains("sfx_stage_win")) // the stage-end passage plays with the outcome text (StageFlow cue)
        #expect(!loss.contains("sfx_base_hit"))
        // Duplicate events collapse to one play.
        let volley = names([
            .weaponFired(entityID: 1, ownerPlayerID: .one, weaponID: "normal", channel: .normal,
                         position: origin, facing: .up),
            .weaponFired(entityID: 2, ownerPlayerID: nil, weaponID: "normal", channel: .normal,
                         position: origin, facing: .down),
        ])
        #expect(volley == ["sfx_fire_normal"])
    }

    @Test func eachWeaponFamilyHasItsOwnLaunchVoice() {
        func launch(_ weaponID: String) -> [String] {
            GameAudio.soundNames(for: [.weaponFired(entityID: 1, ownerPlayerID: nil, weaponID: weaponID,
                                                    channel: .special, position: origin, facing: .up)])
        }
        #expect(launch("rapid") == ["sfx_fire_rapid"])
        #expect(launch("ap") == ["sfx_fire_ap"])
        #expect(launch("explosion") == ["sfx_fire_explosion"])
        #expect(launch("fire") == ["sfx_fire_flame"]) // ignition, not a pellet gun
        #expect(launch("mine") == []) // minePlaced carries the sound
    }

    @Test func hapticCuesTrackThePlayer() {
        func cues(_ events: [DomainEvent]) -> [GameHaptics.Cue] { GameHaptics.cues(for: events) }
        // Only the player's own shot recoils; enemy fire never buzzes.
        #expect(cues([.weaponFired(entityID: 7, ownerPlayerID: .one, weaponID: "normal", channel: .normal,
                                   position: origin, facing: .up)]) == [.recoil])
        #expect(cues([.weaponFired(entityID: 9, ownerPlayerID: nil, weaponID: "normal", channel: .normal,
                                   position: origin, facing: .up)]).isEmpty)
        // Taking damage vs landing a hit.
        #expect(cues([.tankDamaged(entityID: 7, ownerPlayerID: .one, damage: 1, sourceWeaponID: "normal",
                                   position: origin)]) == [.medium])
        #expect(cues([.tankDamaged(entityID: 9, ownerPlayerID: nil, damage: 1, sourceWeaponID: "normal",
                                   position: origin)]) == [.light(intensity: 0.8)])
        // Stage outcome.
        #expect(cues([.stageWon]) == [.success])
        #expect(cues([.stageLost(reason: "base_destroyed")]) == [.error])
    }
}

/// Rapid fire reaches twelve shots a second: own-recoil impacts are throttled
/// so the hand is not buzzed per shot and no frame pays for twelve Taptic
/// calls; every other cue passes untouched.
@MainActor
@Suite struct RecoilThrottleTests {
    @Test func recoilIsThrottledOtherCuesAreNot() {
        let haptics = GameHaptics(clock: { 0 })
        #expect(haptics.admit([.recoil, .recoil, .medium], now: 0) == [.recoil, .medium])
        #expect(haptics.admit([.recoil, .heavy], now: 0.05) == [.heavy])
        #expect(haptics.admit([.recoil], now: 0.12) == [.recoil])
    }

    /// R18-02: the boundary holds at realistic clock origins — 0.119 s
    /// after an admitted recoil is rejected, 0.12 s is admitted.
    @Test(arguments: [0.0, 100.0, 12345.678, 1_000_000.0, 86_400.0 * 3])
    func recoilBoundaryIsExactAtAnyClockOrigin(origin: TimeInterval) {
        let haptics = GameHaptics(clock: { origin })
        #expect(haptics.admit([.recoil], now: origin) == [.recoil])
        #expect(haptics.admit([.recoil, .error], now: origin + 0.119) == [.error])
        #expect(haptics.admit([.recoil], now: origin + 0.12) == [.recoil])
        #expect(haptics.admit([.recoil], now: origin + 0.12 + 0.119) == [])
        #expect(haptics.admit([.recoil], now: origin + 0.24) == [.recoil])
    }
}
