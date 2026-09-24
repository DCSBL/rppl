import MessageUI
import RpplCore
import SwiftUI

enum MailAvailability {
    static var canSend: Bool { MFMailComposeViewController.canSendMail() }
}

enum ParkShare {
    static let feedbackAddress = "rppl@dcsbl.nl"

    /// Writes `<id>.yaml` to a temp folder; nil when encoding or writing fails.
    static func yamlFile(for park: Park) -> URL? {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(park.id).yaml")
            try ParkCatalog.encode(park).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            WakeLog.error(.store, "park share \(park.id): \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    static func share(_ park: Park) {
        guard let url = yamlFile(for: park) else { return }
        ActivitySharePresenter.present(items: [url])
    }

    static var mailBody: String {
        String(localized: "Hi Rppl,\n\nHere is a park I added or updated. The YAML file is attached.\n\nNotes:\n")
    }

    static func subject(for park: Park) -> String {
        String(localized: "Park: \(park.name)")
    }

    /// `mailto:` link for devices without a configured Mail account (`MFMailComposeViewController.canSendMail() == false`).
    /// A `mailto:` URL can't carry an attachment, so the YAML is inlined as a fenced code block instead.
    static func mailtoURL(for park: Park) -> URL? {
        guard let yaml = try? ParkCatalog.encode(park) else { return nil }
        let body = mailBody + "\n```yaml\n" + yaml + "```\n"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject(for: park)),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

struct ParkMailComposer: UIViewControllerRepresentable {
    let park: Park
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([ParkShare.feedbackAddress])
        controller.setSubject(ParkShare.subject(for: park))
        controller.setMessageBody(ParkShare.mailBody, isHTML: false)
        if let url = ParkShare.yamlFile(for: park), let data = try? Data(contentsOf: url) {
            controller.addAttachmentData(data, mimeType: "application/x-yaml", fileName: url.lastPathComponent)
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
