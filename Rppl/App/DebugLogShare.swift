import MessageUI
import RpplCore
import SwiftUI

enum DebugLogShare {
    static let subject = "Rppl debug log"

    /// Writes the raw log to a temp `.txt`; nil when writing fails.
    static func logFile() -> URL? {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("rppl-debug-log.txt")
            try WakeLog.exportText().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            WakeLog.error(.store, "debug log export: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    static func share() {
        guard let url = logFile() else { return }
        ActivitySharePresenter.present(items: [url])
    }

    /// Fallback for devices without a configured Mail account. Plain text in the body (no base64):
    /// line formatting doesn't matter for a log.
    static func mailtoURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ParkShare.feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: WakeLog.exportText()),
        ]
        return components.url
    }
}

struct DebugLogMailComposer: UIViewControllerRepresentable {
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([ParkShare.feedbackAddress])
        controller.setSubject(DebugLogShare.subject)
        controller.setMessageBody("", isHTML: false)
        controller.addAttachmentData(
            Data(WakeLog.exportText().utf8),
            mimeType: "text/plain",
            fileName: "rppl-debug-log.txt"
        )
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish()
        }
    }
}
