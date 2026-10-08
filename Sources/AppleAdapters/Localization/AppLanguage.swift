import Foundation

/// The languages the app speaks (owner 2026-10-08: English, Simplified and
/// Traditional Chinese, Japanese, Korean, Spanish; the phone's language by
/// default, changeable in Settings). The raw value is the `.lproj` folder.
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"

    public var id: String { rawValue }

    /// The language's own name for itself — the one label that must never
    /// be translated, so a player lost in the wrong language can find home.
    public var nativeName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .spanish: "Español"
        }
    }

    /// The phone's choice: the first preferred language the app speaks.
    /// Script matters for Chinese (zh-Hant-TW, zh-HK → Traditional; zh-Hans,
    /// zh-CN, zh-SG → Simplified); region does not matter for the others.
    /// Nothing matched → English.
    public static func matching(preferred: [String]) -> AppLanguage {
        for tag in preferred {
            let lower = tag.lowercased()
            if lower.hasPrefix("zh") {
                if lower.contains("hant") || lower.contains("-tw") || lower.contains("-hk") || lower.contains("-mo") {
                    return .traditionalChinese
                }
                return .simplifiedChinese
            }
            if let language = AppLanguage.allCases.first(where: { lower.hasPrefix($0.rawValue.lowercased()) }) {
                return language
            }
        }
        return .english
    }

    public static var system: AppLanguage { matching(preferred: Locale.preferredLanguages) }
}
