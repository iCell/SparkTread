import Foundation
import Testing
@testable import AppleAdapters

/// The feedback mail (owner 2026-10-09: 直接用 email): addressed to the
/// developer, a localized subject with the version, room to write above a
/// localized prompt, and the diagnostics footer; the mailto fallback
/// carries the same message intact.
@Suite struct FeedbackMailTests {
    private let context = FeedbackMail.Context(appVersion: "1.0", build: "42", system: "iOS 26.0",
                                               device: "iPhone18,1", language: "zh-Hans", difficulty: "casual",
                                               stagesCleared: 5, stageCount: 12)

    @Test func theMessageIsAddressedLocalizedAndCarriesTheFooter() {
        let strings = Strings(language: .simplifiedChinese)
        #expect(FeedbackMail.address == "shawn.lee.im@gmail.com")
        #expect(FeedbackMail.subject(strings, context) == "SparkTread 意见反馈（1.0 (42)）")
        let body = FeedbackMail.body(strings, context)
        #expect(body.hasPrefix("\n\n\n"))
        #expect(body.contains("请在这一行上方写下你的反馈。"))
        #expect(body.contains("iPhone18,1") && body.contains("Difficulty: casual") && body.contains("Stages cleared: 5/12"))
    }

    @Test func theMailtoFallbackKeepsTheMessageIntact() throws {
        let strings = Strings(language: .english)
        let subject = FeedbackMail.subject(strings, context), body = FeedbackMail.body(strings, context) + " a+b"
        let url = try #require(FeedbackMail.mailtoURL(subject: subject, body: body))
        #expect(url.scheme == "mailto" && url.absoluteString.hasPrefix("mailto:shawn.lee.im@gmail.com?"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "subject" }?.value == subject)
        #expect(items.first { $0.name == "body" }?.value == body) // "+" survives as a plus
    }
}
