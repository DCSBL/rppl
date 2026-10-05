import MessageUI
import RpplCore
import SwiftUI

/// Prepared "Send to Rppl" mail: a zipped session export plus the template fields.
struct SessionMail: Identifiable {
    let id = UUID()
    let zipURL: URL
    let subject: String
    let body: String
}

nonisolated enum SessionMailShare {
    /// Most mail providers reject attachments around 20–25 MB; stay below that.
    static let maxAttachmentBytes = 20_000_000

    enum ZipError: LocalizedError {
        case tooLarge(bytes: Int)
        case zipFailed

        var errorDescription: String? {
            switch self {
            case .tooLarge(let bytes):
                let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                let limit = ByteCountFormatter.string(
                    fromByteCount: Int64(SessionMailShare.maxAttachmentBytes),
                    countStyle: .file
                )
                return String(
                    localized: "This session is \(size) zipped, too large to send by mail (limit \(limit)). Use Export instead."
                )
            case .zipFailed:
                return String(localized: "Could not zip the session export.")
            }
        }
    }

    /// Zips `jsonURL` into a temp `<name>.zip`. Uses `NSFileCoordinator` `.forUploading`, which zips a
    /// file or folder without a third-party library. Throws `.tooLarge` above `maxAttachmentBytes`.
    static func zip(_ jsonURL: URL) throws -> URL {
        var coordinationError: NSError?
        var result: Result<URL, Error> = .failure(ZipError.zipFailed)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(jsonURL.deletingPathExtension().lastPathComponent + ".zip")
        NSFileCoordinator().coordinate(
            readingItemAt: jsonURL,
            options: .forUploading,
            error: &coordinationError
        ) { zipped in
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zipped, to: destination)
                result = .success(destination)
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        let url = try result.get()
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard bytes <= maxAttachmentBytes else {
            try? FileManager.default.removeItem(at: url)
            throw ZipError.tooLarge(bytes: bytes)
        }
        return url
    }

    static func subject(manifest: SessionManifest, cityName: String?) -> String {
        let date = manifest.startedAt.formatted(date: .abbreviated, time: .shortened)
        if let cityName, !cityName.isEmpty {
            return String(localized: "Session: \(date), \(cityName)")
        }
        return String(localized: "Session: \(date)")
    }

    static func mailBody(manifest: SessionManifest) -> String {
        let reason = String(localized: "Why I'm sending this session:")
        let details = String(localized: "Session details:")
        return String(localized: "Hi Rppl,\n\nHere is a session export. The zip file is attached.\n")
            + "\n" + reason + "\n\n\n"
            + details + "\n"
            + "- ID: \(manifest.sessionId)\n"
            + "- App: \(manifest.appVersion) (\(manifest.buildNumber))\n"
            + "- Watch: \(manifest.watchModel), \(manifest.systemVersion)\n"
    }
}

struct SessionMailComposer: UIViewControllerRepresentable {
    let mail: SessionMail
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([ParkShare.feedbackAddress])
        controller.setSubject(mail.subject)
        controller.setMessageBody(mail.body, isHTML: false)
        if let data = try? Data(contentsOf: mail.zipURL) {
            controller.addAttachmentData(data, mimeType: "application/zip", fileName: mail.zipURL.lastPathComponent)
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
