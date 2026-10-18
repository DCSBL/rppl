import Foundation

/// Subject and body of the "Need help or report a bug?" mail. Always English: it goes to the developer,
/// whatever the rider's language.
public struct SupportRequest: Equatable, Sendable {
    public static let subject = "I have a question or comment about Rppl"

    public var appVersion: String
    public var deviceModel: String
    public var systemVersion: String

    public init(appVersion: String, deviceModel: String, systemVersion: String) {
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
    }

    public var body: String {
        """
        Please describe your question, comment or bug here:



        What did you expect to happen?



        ----- App and device details (please keep) -----
        App version: \(appVersion)
        Device: \(deviceModel)
        iOS version: \(systemVersion)
        """
    }
}
