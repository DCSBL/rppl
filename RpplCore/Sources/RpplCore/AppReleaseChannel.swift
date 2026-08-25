import Foundation

/// Distribution channel helpers for gated debug / TestFlight-only surfaces.
public enum AppReleaseChannel {
    /// Debug builds and TestFlight (sandbox receipt). App Store release stays off.
    public static var allowsDebugTools: Bool {
        #if DEBUG
        true
        #else
        isTestFlight
        #endif
    }

    /// TestFlight installs use the sandbox App Store receipt name.
    public static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}
