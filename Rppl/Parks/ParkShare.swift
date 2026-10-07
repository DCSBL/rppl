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

    static let blockStart = "----- START RPPL PARK -----"
    static let blockEnd = "----- END RPPL PARK -----"

    /// `changedSections` lists which parts of the park were edited; `attached` says whether the YAML is a
    /// file on the mail or base64 below the text.
    static func mailBody(park: Park, changedSections: [ParkSection] = [], attached: Bool) -> String {
        let intro = attached
            ? String(localized: "I edited some information about \(park.name). The YAML file is attached. Can you review this so it can be shown to other riders?")
            : String(localized: "I edited some information about \(park.name). This is sent as base64 below. Can you review this so it can be shown to other riders?")
        var body = String(localized: "Hi there,") + "\n\n" + intro + "\n\n"
        if !changedSections.isEmpty {
            let list = changedSections.enumerated()
                .map { $0.offset == 0 ? $0.element.label : $0.element.label.lowercased() }
                .joined(separator: ", ")
            body += String(localized: "The following data was changed: \(list).") + "\n\n"
        }
        body += String(localized: "Thanks!") + "\n"
        return body
    }

    /// The full YAML as base64 (64-character lines) between a start and an end line, like an armored public key.
    static func armoredBlock(for yaml: String) -> String {
        let encoded = Data(yaml.utf8).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return [blockStart, encoded, blockEnd].joined(separator: "\n")
    }

    static func subject(for park: Park) -> String {
        String(localized: "Edited park: \(park.name)")
    }

    /// `mailto:` link for devices without a configured Mail account (`MFMailComposeViewController.canSendMail() == false`).
    /// A `mailto:` URL can't carry an attachment, so the YAML goes in the body instead. Third-party mail apps (e.g.
    /// Proton Mail) tend to flatten leading whitespace in a `mailto:` body, which breaks YAML indentation, so it's
    /// base64-encoded rather than inlined as plain text.
    static func mailtoURL(for park: Park, changedSections: [ParkSection] = []) -> URL? {
        guard let yaml = try? ParkCatalog.encode(park) else { return nil }
        var body = mailBody(park: park, changedSections: changedSections, attached: false)
        body += "\n" + armoredBlock(for: yaml) + "\n"
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
        let body = ParkShare.mailBody(park: park, changedSections: changedSections, attached: true)
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
