import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MessageUI)
import MessageUI
#endif

/// The feedback channel (owner 2026-10-09: 直接用 email): a mail to the
/// developer, written by the player in their own mail app — no SDK, no
/// server, nothing collected unless the player sends it. The message
/// carries a short diagnostics footer (version, system, device, language,
/// difficulty, progress) so a report can be read without a reply asking for
/// them; the player sees all of it before sending.
enum FeedbackMail {
    static let address = "shawn.lee.im@gmail.com"

    /// What the footer reports.
    struct Context: Equatable {
        var appVersion: String
        var build: String
        var system: String
        var device: String
        var language: String
        var difficulty: String
        var stagesCleared: Int
        var stageCount: Int
    }

    static func subject(_ strings: Strings, _ context: Context) -> String {
        strings("feedback.subject", "\(context.appVersion) (\(context.build))")
    }

    /// Room to write at the top, the prompt line, then the footer — the
    /// footer in English: it is read by the developer, whatever the
    /// player's language.
    static func body(_ strings: Strings, _ context: Context) -> String {
        """



        —— \(strings("feedback.prompt")) ——
        SparkTread \(context.appVersion) (\(context.build))
        \(context.system) · \(context.device)
        Language: \(context.language) · Difficulty: \(context.difficulty)
        Stages cleared: \(context.stagesCleared)/\(context.stageCount)
        """
    }

    /// The same message for the system's default mail app.
    static func mailtoURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        // URLComponents leaves "+" alone, and mail apps read it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// The running app and device.
    static func currentContext(language: String, difficulty: String, stagesCleared: Int, stageCount: Int) -> Context {
        let info = Bundle.main.infoDictionary ?? [:]
        var machine = "unknown"
        var system = ProcessInfo.processInfo.operatingSystemVersionString
        #if canImport(UIKit)
        system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #endif
        var name = utsname()
        if uname(&name) == 0 {
            machine = withUnsafeBytes(of: &name.machine) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        return Context(appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
                       build: info["CFBundleVersion"] as? String ?? "?",
                       system: system, device: machine, language: language, difficulty: difficulty,
                       stagesCleared: stagesCleared, stageCount: stageCount)
    }
}

/// The settings row's action: the system mail composer when a Mail account
/// is set up; otherwise the default mail app through a mailto link;
/// otherwise a dialog with the address and a button to copy it.
struct FeedbackButton: View {
    let context: FeedbackMail.Context
    @Environment(\.strings) private var strings
    @Environment(\.openURL) private var openURL
    @State private var composing = false
    @State private var noMail = false

    var body: some View {
        PlateButton(title: strings("settings.feedback.send"), icon: "envelope.fill", size: .small) { send() }
            #if canImport(MessageUI)
            .sheet(isPresented: $composing) {
                MailComposer(subject: FeedbackMail.subject(strings, context),
                             body: FeedbackMail.body(strings, context)) { composing = false }
                    .ignoresSafeArea()
            }
            #endif
            .alert(strings("feedback.noMail.title"), isPresented: $noMail) {
                Button(strings("feedback.copyAddress")) { copyAddress() }
                Button(strings("common.close"), role: .cancel) {}
            } message: {
                Text(strings("feedback.noMail.message", FeedbackMail.address))
            }
    }

    private func send() {
        #if canImport(MessageUI)
        if MFMailComposeViewController.canSendMail() { composing = true; return }
        #endif
        guard let url = FeedbackMail.mailtoURL(subject: FeedbackMail.subject(strings, context),
                                               body: FeedbackMail.body(strings, context)) else {
            noMail = true
            return
        }
        openURL(url) { accepted in if !accepted { noMail = true } }
    }

    private func copyAddress() {
        #if canImport(UIKit)
        UIPasteboard.general.string = FeedbackMail.address
        #endif
    }
}

#if canImport(MessageUI)
/// The system mail composer, addressed and filled in.
private struct MailComposer: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackMail.address])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish()
        }
    }
}
#endif
