import MessageUI
import RpplCore
import SwiftUI
import UIKit

enum SupportMail {
    static var request: SupportRequest {
        SupportRequest(
            appVersion: AppVersionInfo(infoDictionary: Bundle.main.infoDictionary).headline,
            deviceModel: deviceIdentifier,
            systemVersion: UIDevice.current.systemVersion
        )
    }

    /// Hardware identifier such as `iPhone17,1`; `UIDevice.model` only says "iPhone".
    private static var deviceIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    /// Fallback for devices without a configured Mail account.
    static func mailtoURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ParkShare.feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: SupportRequest.subject),
            URLQueryItem(name: "body", value: request.body),
        ]
        return components.url
    }
}

struct SupportMailComposer: UIViewControllerRepresentable {
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([ParkShare.feedbackAddress])
        controller.setSubject(SupportRequest.subject)
        controller.setMessageBody(SupportMail.request.body, isHTML: false)
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
