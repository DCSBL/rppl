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

    /// `diff` is the base64 of the changed YAML lines against the bundled version (nil for a brand-new park).
    /// `yaml` is the base64 of the full file; nil when the file is attached instead.
    static func mailBody(diff: String?, yaml: String?) -> String {
        var body = String(localized: "Hi Rppl,\n\nHere is a suggested change to a park.\n\nNotes:\n")
        if let diff {
            body += "\n" + String(localized: "Diff (base64-encoded, decode before reading):") + "\n" + diff + "\n"
        }
        if let yaml {
            body += "\n" + String(localized: "YAML (base64-encoded, decode before reading):") + "\n" + yaml + "\n"
        }
        return body
    }

    /// Base64 of the changed YAML lines; nil when there is nothing to compare against or nothing changed.
    static func encodedDiff(for park: Park, bundledPark: Park?) -> String? {
        guard let bundledPark,
              let old = try? ParkCatalog.encode(bundledPark),
              let new = try? ParkCatalog.encode(park) else { return nil }
        let diff = ParkDiff.lineDiff(from: old, to: new)
        return diff.isEmpty ? nil : Data(diff.patchText.utf8).base64EncodedString()
    }

    static func subject(for park: Park) -> String {
        String(localized: "A suggested change to \(park.name)")
    }

    /// `mailto:` link for devices without a configured Mail account (`MFMailComposeViewController.canSendMail() == false`).
    /// A `mailto:` URL can't carry an attachment, so the YAML goes in the body instead. Third-party mail apps (e.g.
    /// Proton Mail) tend to flatten leading whitespace in a `mailto:` body, which breaks YAML indentation, so it's
    /// base64-encoded rather than inlined as plain text.
    static func mailtoURL(for park: Park, bundledPark: Park?) -> URL? {
        guard let yaml = try? ParkCatalog.encode(park) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject(for: park)),
            URLQueryItem(
                name: "body",
                value: mailBody(
                    diff: encodedDiff(for: park, bundledPark: bundledPark),
                    yaml: Data(yaml.utf8).base64EncodedString()
                )
            ),
        ]
        return components.url
    }
}

struct ParkMailComposer: UIViewControllerRepresentable {
    let park: Park
    let bundledPark: Park?
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([ParkShare.feedbackAddress])
        controller.setSubject(ParkShare.subject(for: park))
        let body = ParkShare.mailBody(diff: ParkShare.encodedDiff(for: park, bundledPark: bundledPark), yaml: nil)
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
