import Foundation
import Testing
@testable import AppleAdapters

/// Six languages, the phone's by default, changeable in Settings (owner
/// 2026-10-08). The catalog must be complete in every language — a missing
/// key shows as the key — and the phone's choice must resolve by script
/// for Chinese and by language for the rest.
@Suite struct LocalizationTests {
    /// Every key the English table has, every other language has too.
    @Test func everyLanguageCoversEveryKey() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("Sources/AppleAdapters/Resources/Localizable.xcstrings"))) as? [String: Any]
        let entries = try #require(catalog?["strings"] as? [String: Any])
        #expect(entries.count > 100)
        for language in AppLanguage.allCases {
            let strings = Strings(language: language)
            for key in entries.keys {
                #expect(strings.has(key), "\(language.rawValue) lacks \(key)")
                #expect(strings(key) != key, "\(language.rawValue) shows the key for \(key)")
            }
        }
    }

    @Test func thePhonesLanguageResolvesByScriptForChineseAndByLanguageOtherwise() {
        #expect(AppLanguage.matching(preferred: ["zh-Hant-TW", "en"]) == .traditionalChinese)
        #expect(AppLanguage.matching(preferred: ["zh-HK"]) == .traditionalChinese)
        #expect(AppLanguage.matching(preferred: ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.matching(preferred: ["zh-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.matching(preferred: ["ja-JP", "en"]) == .japanese)
        #expect(AppLanguage.matching(preferred: ["ko-KR"]) == .korean)
        #expect(AppLanguage.matching(preferred: ["es-MX"]) == .spanish)
        #expect(AppLanguage.matching(preferred: ["en-GB"]) == .english)
        // Unsupported first, supported second: the second wins.
        #expect(AppLanguage.matching(preferred: ["fr-FR", "ja"]) == .japanese)
        // Nothing supported: English.
        #expect(AppLanguage.matching(preferred: ["fr-FR", "de-DE"]) == .english)
        #expect(AppLanguage.matching(preferred: []) == .english)
    }

    @Test func formattedStringsTakeTheirArguments() {
        let zh = Strings(language: .simplifiedChinese), en = Strings(language: .english)
        #expect(zh("stage.title", 7) == "STAGE 07")
        #expect(en("results.score", "1200") == "Score 1200")
        #expect(Strings(language: .japanese)("stage.title", 12) == "ステージ 12")
    }

    /// Settings persist through their defaults suite and come back; the
    /// language falls back to the phone when none is chosen.
    @Test @MainActor func settingsRoundTrip() throws {
        let suite = "sparktread.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.language == nil && store.soundEnabled && store.soundVolume == 1 && !store.mirrorControls)
        #expect(store.effectiveLanguage == .system)
        store.language = .korean
        store.soundVolume = 0.5
        store.mirrorControls = true
        store.reduceMotion = true
        let again = SettingsStore(defaults: defaults)
        #expect(again.language == .korean && again.soundVolume == 0.5 && again.mirrorControls && again.reduceMotion)
        #expect(again.effectiveLanguage == .korean && again.strings("settings.title") == "설정")
        again.language = nil
        #expect(SettingsStore(defaults: defaults).language == nil)
    }
}
