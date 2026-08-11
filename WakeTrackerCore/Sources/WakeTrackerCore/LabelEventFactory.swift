import Foundation

public enum LabelEventFactory {
    public static func make(
        code: String,
        timestamp: Date = Date(),
        id: String = UUID().uuidString,
        gps: GPSSnapshot? = nil,
        waterSubmersionState: String? = nil,
        waterTemperatureCelsius: Double? = nil,
        motionActivity: String? = nil
    ) -> LabelEvent {
        LabelEvent(
            id: id,
            code: code,
            timestamp: timestamp,
            gps: gps,
            waterSubmersionState: waterSubmersionState,
            waterTemperatureCelsius: waterTemperatureCelsius,
            motionActivity: motionActivity
        )
    }

    public static func gpsSnapshot(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double,
        verticalAccuracy: Double? = nil,
        speed: Double?,
        course: Double?,
        timestamp: Date
    ) -> GPSSnapshot {
        GPSSnapshot(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            speed: (speed ?? -1) >= 0 ? speed : nil,
            course: (course ?? -1) >= 0 ? course : nil,
            timestamp: timestamp
        )
    }
}

public enum TransferPendingFilter {
    /// Manifests that still need a successful phone ack.
    public static func needingTransfer(_ manifests: [SessionManifest]) -> [SessionManifest] {
        manifests.filter { manifest in
            switch manifest.transferState {
            case .readyToTransfer, .transferring:
                return true
            case .recording, .acknowledged:
                return false
            }
        }
    }
}
