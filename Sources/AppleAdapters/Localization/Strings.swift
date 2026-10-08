import Foundation
import SwiftUI

/// The app's strings in one language, looked up by key from the string
/// catalog (`Resources/Localizable.xcstrings`). Built once per language
/// change and handed down the view tree through the environment, so the
/// in-app language choice applies at once without relaunching — which is
/// why views do not use `Text("key")`'s own lookup, which follows the
/// process locale. A missing key returns the key itself, loudly.
public struct Strings: Sendable {
    public let language: AppLanguage
    private let table: [String: String]

    public init(language: AppLanguage) {
        self.language = language
        table = Self.load(language) ?? Self.load(.english) ?? [:]
    }

    /// The compiled table for a language, read as a plist: on iOS
    /// `Bundle.url(forResource: "ja", withExtension: "lproj")` finds nothing
    /// — CFBundle does not hand out localization folders as resources, which
    /// is how every lookup failed under the Xcode test run while passing
    /// under `swift test` on macOS (2026-10-08) — but asking for the strings
    /// file with its `localization` works on both.
    private static func load(_ language: AppLanguage) -> [String: String]? {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "strings",
                                          subdirectory: nil, localization: language.rawValue),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return nil }
        return plist
    }

    public func callAsFunction(_ key: String) -> String {
        table[key] ?? key
    }

    /// A string with `%@` / `%d` arguments.
    public func callAsFunction(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: self(key), locale: nil, arguments: arguments)
    }

    /// Whether the catalog has this key in this language (tests).
    public func has(_ key: String) -> Bool { table[key] != nil }
}

private struct StringsKey: EnvironmentKey {
    static let defaultValue = Strings(language: .english)
}

extension EnvironmentValues {
    public var strings: Strings {
        get { self[StringsKey.self] }
        set { self[StringsKey.self] = newValue }
    }
}
