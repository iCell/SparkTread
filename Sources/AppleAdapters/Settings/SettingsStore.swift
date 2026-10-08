import Foundation
import Observation

/// The player's settings (owner 2026-10-08): language, sound, haptics, the
/// controls' handedness, and the accessibility options. One observable
/// object at the app's root, written through to `UserDefaults` on every
/// change and read back at launch. Gameplay rules never live here — these
/// are presentation and input preferences, and none of them reaches the
/// simulation or a recording.
@Observable
public final class SettingsStore {
    /// nil = not chosen yet: the phone's language, English if the phone's
    /// is not one of the six (`AppLanguage.system`). Settings shows that
    /// one selected; there is no separate "system" choice.
    public var language: AppLanguage? { didSet { write("language", language?.rawValue) } }
    public var soundEnabled: Bool { didSet { write("soundEnabled", soundEnabled) } }
    /// 0…1, applied over every cue's own level.
    public var soundVolume: Double { didSet { write("soundVolume", soundVolume) } }
    public var hapticsEnabled: Bool { didSet { write("hapticsEnabled", hapticsEnabled) } }
    /// Stick on the right, fire buttons on the left (GAME_RULES §15.2
    /// allows the mirror).
    public var mirrorControls: Bool { didSet { write("mirrorControls", mirrorControls) } }
    /// Accessibility: no launch drive, no shake, no HUD fades.
    public var reduceMotion: Bool { didSet { write("reduceMotion", reduceMotion) } }
    /// Accessibility: an opaque HUD that never thins out.
    public var highContrastHUD: Bool { didSet { write("highContrastHUD", highContrastHUD) } }
    /// Accessibility: the HUD at 1.3× its size.
    public var largeHUD: Bool { didSet { write("largeHUD", largeHUD) } }

    private let defaults: UserDefaults
    private static let prefix = "settings."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func read<T>(_ key: String, _ fallback: T) -> T {
            (defaults.object(forKey: Self.prefix + key) as? T) ?? fallback
        }
        language = read("language", "").isEmpty ? nil : AppLanguage(rawValue: read("language", ""))
        soundEnabled = read("soundEnabled", true)
        soundVolume = read("soundVolume", 1.0)
        hapticsEnabled = read("hapticsEnabled", true)
        mirrorControls = read("mirrorControls", false)
        reduceMotion = read("reduceMotion", false)
        highContrastHUD = read("highContrastHUD", false)
        largeHUD = read("largeHUD", false)
    }

    /// The language in force: the chosen one, else the phone's.
    public var effectiveLanguage: AppLanguage { language ?? .system }

    public var strings: Strings { Strings(language: effectiveLanguage) }

    private func write(_ key: String, _ value: Any?) {
        if let value { defaults.set(value, forKey: Self.prefix + key) } else { defaults.removeObject(forKey: Self.prefix + key) }
    }
}
