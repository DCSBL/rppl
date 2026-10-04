import MessageUI
import RpplCore
import SwiftUI

/// "Share with Rppl": the anonymized session (`SessionAnonymizer`) by mail. Which route the file
/// takes is decided in Core (`SessionShareMail.route`); this file only holds the Apple-only parts.
enum SessionRpplShare {
    static var subject: String { String(localized: "Session for Rppl") }

    /// Body above the attachment, with room for the sender's notes.
    static var attachmentBody: String {
        String(localized: "Hi Rppl,\n\nHere is a session from my logbook. Its location and personal details are anonymized. The session file is attached.\n\nNotes:\n")
    }

    /// `mailto:` link for a device without a configured Mail account. A `mailto:` link cannot carry
    /// an attachment, so the session file goes in the body as base64.
    static func mailtoURL(fileData: Data) -> URL? {
        let body = String(localized: "Hi Rppl,\n\nHere is a session from my logbook. Its location and personal details are anonymized. The session file is base64-encoded below.\n\nNotes:\n")
            + "\n" + String(localized: "Session file (base64-encoded, decode before reading):") + "\n"
            + SessionShareMail.base64Body(for: fileData)
        return SessionShareMail.mailtoURL(recipient: ParkShare.feedbackAddress, subject: subject, body: body)
    }
}

struct SessionMailComposer: UIViewControllerRepresentable {
    let fileURL: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([ParkShare.feedbackAddress])
        controller.setSubject(SessionRpplShare.subject)
        controller.setMessageBody(SessionRpplShare.attachmentBody, isHTML: false)
        if let data = try? Data(contentsOf: fileURL) {
            controller.addAttachmentData(data, mimeType: "application/json", fileName: fileURL.lastPathComponent)
        }
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
