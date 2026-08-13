import Foundation

/// Schema version for on-disk session packages. Bump when breaking changes land.
public enum SessionSchema {
    /// v2: motion stored as framed zlib JSONL (`motion-NNN.jsonl.zlib`); transfer may carry `motionFramesZlib`.
    public static let currentVersion = 2
}

/// Opaque segment codes (not a closed enum — unknown codes must round-trip).
public enum LabelCodes {
    public static let waiting = "waiting"
    public static let riding = "riding"
    public static let swimming = "swimming"
    public static let walking = "walking"
}
