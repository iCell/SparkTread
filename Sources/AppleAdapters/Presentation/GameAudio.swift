import AVFoundation
import GameCore

/// One playable sound instance. `AVAudioPlayer` satisfies this directly;
/// tests inject a fake so lifecycle behaviour is asserted without audio
/// hardware.
public protocol AudioVoice: AnyObject {
    var isPlaying: Bool { get }
    var volume: Float { get set }
    var numberOfLoops: Int { get set }
    var currentTime: TimeInterval { get set }
    @discardableResult func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
    func stop()
}

extension AVAudioPlayer: AudioVoice {}

/// Creates voices for sound names and owns the platform audio session.
public protocol AudioBackend {
    func activateSession()
    func makeVoice(named name: String) -> AudioVoice?
}

/// The production backend: bundle WAVs through AVAudioPlayer.
public struct AVAudioBackend: AudioBackend {
    public init() {}

    public func activateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    public func makeVoice(named name: String) -> AudioVoice? {
        guard let url = GameAudio.soundURL(name), let player = try? AVAudioPlayer(contentsOf: url) else {
            return nil
        }
        return player
    }
}

/// M3 provisional SFX (apple_adapters/Audio, §14): plays the synthesized
/// placeholder set for this tick's domain events. Reference scope: game SFX
/// plus win/loss stingers, no music. The sound CONTENT is provisional
/// (owner decision 2026-09-09: replicate the reference game's voices once
/// the reference material is available); this class owns the structural
/// rules — which event plays what, dedup per drain, priorities, throttles,
/// and the suspend/mute lifecycle.
///
/// Playback: a small pool of preloaded voices per sound so rapid fire
/// overlaps without allocation churn. Everything stays on the main actor;
/// the simulation never depends on audio.
@MainActor
public final class GameAudio {
    public nonisolated static let allSounds: [String] = [
        "sfx_fire_normal", "sfx_fire_special", "sfx_fire_rapid",
        "sfx_fire_ap", "sfx_fire_explosion", "sfx_fire_flame",
        "sfx_flame_loop", "sfx_dry_fire",
        "sfx_hit_brick", "sfx_hit_steel", "sfx_deflect", "sfx_hit_tank",
        "sfx_tank_explode", "sfx_player_explode", "sfx_explosion_blast",
        "sfx_base_hit", "sfx_base_own_hit", "sfx_base_destroyed", "sfx_base_shield_on",
        "sfx_pickup_spawn", "sfx_pickup_collect", "sfx_mine_place",
        "sfx_spawn_warp", "sfx_stage_win",
        "sfx_tally_tick", "sfx_stage_card",
    ]


    /// Minimum wall-clock spacing between dry-fire clicks (§12.4 "quiet
    /// dry-fire sound with cooldown to avoid spam"); the simulation's channel
    /// cooldown is the primary rate limit, this is presentation defence.
    public nonisolated static let dryFireMinimumInterval: TimeInterval = 0.35

    public nonisolated static func soundURL(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "wav",
                          subdirectory: "Audio")
    }

    private let backend: AudioBackend
    /// Monotonic clock (uptime) for throttles — never calendar time.
    private let clock: () -> TimeInterval
    private var pools: [String: [AudioVoice]] = [:]
    /// Voices pre-warmed per sound. Rapid fire launches every 83 ms at the
    /// fastest cadence while its 340 ms excerpt is still playing — up to
    /// five clips overlap — so it needs more voices than any other cue for
    /// every launch to stay audible (six: one of headroom); playback never
    /// allocates beyond this.
    nonisolated static func poolSize(for name: String) -> Int {
        name == "sfx_fire_rapid" ? 6 : 3
    }
    /// Looping ambience keyed by name: the DESIRED state survives a
    /// suspension; the voice is only alive while playing.
    private var loops: [String: (voice: AudioVoice?, volume: Float)] = [:]
    /// A loop whose backend start failed is retried no sooner than this
    /// (per name) — never once per frame.
    private var loopRetryNotBefore: [String: TimeInterval] = [:]
    private var lastDryFireTime: TimeInterval?
    public private(set) var isSuspended = false

    /// Mute: stops everything now and refuses new playback until re-enabled.
    public var isEnabled = true {
        didSet { if !isEnabled { stopAllVoices() } }
    }

    public init(backend: AudioBackend = AVAudioBackend(),
                clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.backend = backend
        self.clock = clock
        backend.activateSession()
        // Pools are pre-warmed to their full size at construction: creating
        // a voice is a synchronous file load, which must never happen on a
        // frame in the middle of a rapid-fire run.
        for name in Self.allSounds {
            var pool: [AudioVoice] = []
            for _ in 0..<Self.poolSize(for: name) {
                guard let voice = backend.makeVoice(named: name) else { break }
                voice.prepareToPlay()
                pool.append(voice)
            }
            if !pool.isEmpty { pools[name] = pool }
        }
    }

    // MARK: - Lifecycle

    /// Application lost the foreground: silence everything; remember which
    /// loops were wanted.
    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        stopAllVoices()
    }

    /// Back in the foreground: restart wanted loops, never historical
    /// one-shots.
    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        for (name, entry) in loops.sorted(by: { $0.key < $1.key }) where isEnabled {
            startLoop(name, volume: entry.volume)
        }
    }

    /// A new world: nothing from the old one keeps playing (loops AND
    /// one-shots), throttles start fresh; ambience is re-derived by the
    /// scene from the new state.
    public func resetForNewWorld() {
        lastDryFireTime = nil
        loopRetryNotBefore.removeAll()
        for name in loops.keys.sorted() { setLoop(name, active: false) }
        stopAllVoices()
    }

    private func stopAllVoices() {
        for pool in pools.values { for voice in pool where voice.isPlaying { voice.stop() } }
        for name in loops.keys.sorted() {
            loops[name]?.voice?.stop()
            loops[name]?.voice = nil
        }
    }

    // MARK: - Playback

    /// Looping ambience (e.g. burning flame patches): idempotent start/stop;
    /// a volume change applies to the running loop. The wanted state is
    /// reconciled against ACTUAL playback: a voice the platform stopped
    /// (interruption) or that failed to start is restarted, with a one-
    /// second backoff so a persistent backend failure never allocates per
    /// frame.
    public func setLoop(_ name: String, active: Bool, volume: Float = 0.5) {
        if active {
            var entry = loops[name] ?? (nil, volume)
            entry.volume = volume
            entry.voice?.volume = volume
            if let voice = entry.voice, !voice.isPlaying { entry.voice = nil }
            loops[name] = entry
            if entry.voice == nil, !isSuspended, isEnabled { startLoop(name, volume: volume) }
        } else if let entry = loops.removeValue(forKey: name) {
            entry.voice?.stop()
        }
    }

    private func startLoop(_ name: String, volume: Float) {
        let now = clock()
        if let notBefore = loopRetryNotBefore[name], now < notBefore { return }
        guard let voice = backend.makeVoice(named: name) else {
            loopRetryNotBefore[name] = now + 1
            return
        }
        voice.numberOfLoops = -1
        voice.volume = volume
        guard voice.play(), voice.isPlaying else {
            loopRetryNotBefore[name] = now + 1
            return
        }
        loopRetryNotBefore[name] = nil
        loops[name] = (voice, volume)
    }

    /// Returns whether a voice actually started. Playback never allocates:
    /// the pools are warmed at construction, and when no pooled voice is
    /// free the request is DROPPED — never satisfied by restarting a playing
    /// voice, and never by creating one (a synchronous file load) in the
    /// middle of a rapid-fire run. Hypothesis behind the policy: a
    /// seek-and-restart or a load on the main thread at twelve shots a
    /// second is a plausible source of the stutter the owner reported; it
    /// is not profiled. A fourth overlapping launch of the same 130 ms
    /// sound is inaudible anyway. A pool that came up short at construction
    /// stays short (R18-01): recovery would belong outside gameplay.
    @discardableResult
    public func play(_ name: String, volume: Float = 1.0) -> Bool {
        guard isEnabled, !isSuspended, let pool = pools[name],
              let chosen = pool.first(where: { !$0.isPlaying }) else { return false }
        chosen.volume = volume
        chosen.currentTime = 0
        return chosen.play()
    }

    /// Plays one drain's events: at most one play per sound name, base
    /// priority applied per drain (a drain may span several ticks — the
    /// priority is per presentation batch, documented), dry fire throttled.
    /// The throttle commits only when a click actually played: ignored
    /// requests (muted, suspended) never silence later real ones.
    public func play(events: [DomainEvent]) {
        for name in Self.soundNames(for: events) {
            if name == "sfx_dry_fire" {
                guard isEnabled, !isSuspended else { continue }
                let now = clock()
                if let last = lastDryFireTime, now - last < Self.dryFireMinimumInterval { continue }
                if play(name) { lastDryFireTime = now }
                continue
            }
            play(name)
        }
    }

    /// Pure event→sound resolution, separated for tests. Impact voices come
    /// from the structured impact kinds — no inference from co-occurring
    /// events. §12.4: base damage has priority over routine weapon voices,
    /// so a batch with a base hit drops the launch voices of that batch.
    public nonisolated static func soundNames(for events: [DomainEvent]) -> [String] {
        var names: [String] = []
        let stageDecided = events.contains {
            if case .stageWon = $0 { return true }
            if case .stageLost = $0 { return true }
            return false
        }
        func add(_ name: String) {
            if !names.contains(name) { names.append(name) }
        }
        func impactVoice(_ impact: ImpactTarget) -> String? {
            switch impact {
            case .brick: "sfx_hit_brick"
            case .steel, .boundary: "sfx_hit_steel"
            case .deflected, .projectile, .mine: "sfx_deflect"
            case .tank, .base, .expired, .explosion: nil // carried by damage/explosion events
            }
        }
        for event in events {
            switch event {
            case .weaponFired(_, _, let weaponID, let channel, _, _):
                // Each family has its own launch voice — a flame thrower
                // must sound like ignition, not a pellet gun.
                switch weaponID {
                case "normal": add("sfx_fire_normal")
                case "rapid": add("sfx_fire_rapid")
                case "ap": add("sfx_fire_ap")
                case "explosion": add("sfx_fire_explosion")
                case "fire": add("sfx_fire_flame")
                case "mine": break // minePlaced carries the sound
                default: add(channel == .special ? "sfx_fire_special" : "sfx_fire_normal")
                }
            case .dryFire(_, let owner, _):
                if owner != nil { add("sfx_dry_fire") } // player only (§12.4)
            case .projectileHit(_, _, _, let impact), .projectileDestroyed(_, _, _, let impact):
                if let voice = impactVoice(impact) { add(voice) }
            case .tankDamaged:
                add("sfx_hit_tank")
            case .tankShieldHit:
                add("sfx_deflect")
            case .tankDestroyed(_, let owner, _):
                add(owner != nil ? "sfx_player_explode" : "sfx_tank_explode")
            case .explosion:
                add("sfx_explosion_blast")
            case .minePlaced:
                add("sfx_mine_place")
            case .mineRemoved:
                add("sfx_deflect")
            case .baseDamaged(_, _, let allied):
                // ADR-0005: an own-fire hit is never mistaken for a
                // breakthrough — distinct voice, also on the killing blow.
                if allied { add("sfx_base_own_hit") } else if !stageDecided { add("sfx_base_hit") }
            case .baseShieldChanged(let active):
                if active { add("sfx_base_shield_on") }
            case .pickupSpawned:
                add("sfx_pickup_spawn")
            case .pickupCollected:
                add("sfx_pickup_collect")
            case .enemyWaveStarted:
                add("sfx_spawn_warp")
            case .directorPhaseStarted:
                add("sfx_spawn_warp") // the elite wave's own warp, ahead of its telegraphs
            case .baseRepaired:
                add("sfx_base_shield_on")
            case .stageWon:
                break // the outcome stinger plays with the outro fade (StageFlow cue)
            case .stageLost(let reason):
                if reason == "base_destroyed" { add("sfx_base_destroyed") }
            default:
                break
            }
        }
        let basePriority = ["sfx_base_hit", "sfx_base_own_hit", "sfx_base_destroyed"]
        if names.contains(where: basePriority.contains) {
            names.removeAll { $0.hasPrefix("sfx_fire_") } // every launch voice
        }
        return names
    }
}
