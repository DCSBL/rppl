import Foundation

/// Watch sensor rate policy keyed off live detection code.
public enum SensorSamplingMode {
    /// Dense GPS + full-rate device motion while riding or during unsure GPS gaps.
    public static func isDense(currentCode: String) -> Bool {
        let code = DetectionCodes.normalize(currentCode)
        return code == DetectionCodes.riding || code == DetectionCodes.unsure
    }
}
