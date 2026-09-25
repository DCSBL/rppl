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

    /// `changedSections` is a "these sections are changed" summary, not a field-by-field diff.
    /// `yamlNote` describes where the recipient finds the YAML (attached vs. inlined below).
    static func mailBody(changedSections: [ParkSection] = [], yamlNote: String) -> String {
        var body = String(localized: "Hi Rppl,\n\nHere is a park I added or updated. \(yamlNote)\n")
        if !changedSections.isEmpty {
            let list = changedSections.map { "- \($0.label)" }.joined(separator: "\n")
            body += "\n" + String(localized: "Changed sections:") + "\n" + list + "\n"
        }
        body += "\n" + String(localized: "Notes:") + "\n"
        return body
    }

    static func subject(for park: Park) -> String {
        String(localized: "Park: \(park.name)")
    }

    /// `mailto:` link for devices without a configured Mail account (`MFMailComposeViewController.canSendMail() == false`).
    /// A `mailto:` URL can't carry an attachment, so the YAML goes in the body instead. Third-party mail apps (e.g.
    /// Proton Mail) tend to flatten leading whitespace in a `mailto:` body, which breaks YAML indentation, so it's
    /// base64-encoded rather than inlined as plain text.
    static func mailtoURL(for park: Park, changedSections: [ParkSection] = []) -> URL? {
        guard let yaml = try? ParkCatalog.encode(park) else { return nil }
        let encoded = Data(yaml.utf8).base64EncodedString()
        let body = mailBody(
            changedSections: changedSections,
            yamlNote: String(localized: "The YAML is base64-encoded below.")
        ) + "\n" + String(localized: "YAML (base64-encoded, decode before reading):") + "\n" + encoded + "\n"
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

extension ParkSection {
    var label: String {
        switch self {
        case .basics: String(localized: "Basics")
        case .location: String(localized: "Location")
        case .contact: String(localized: "Contact")
        case .about: String(localized: "About")
        case .cables: String(localized: "Cables")
        case .opening: String(localized: "Opening")
        case .prices: String(localized: "Prices")
        case .links: String(localized: "Links")
        }
    }
}

struct ParkMailComposer: UIViewControllerRepresentable {
    let park: Park
    let changedSections: [ParkSection]
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([ParkShare.feedbackAddress])
        controller.setSubject(ParkShare.subject(for: park))
        let body = ParkShare.mailBody(
            changedSections: changedSections,
            yamlNote: String(localized: "The YAML file is attached.")
        )
        controller.setMessageBody(body, isHTML: false)
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
