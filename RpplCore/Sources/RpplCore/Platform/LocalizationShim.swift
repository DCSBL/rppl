#if !canImport(Darwin)
import Foundation

extension String {
    /// Linux (CI) Foundation has no `bundle:` overload and SwiftPM does not compile `.xcstrings`
    /// there; the key is the English source text, so returning it is the correct fallback.
    /// Apple builds use the real `String(localized:table:bundle:locale:comment:)`.
    /// Keys with interpolation resolve to the interpolated English text.
    init(localized key: String, bundle: Bundle, comment: StaticString? = nil) {
        self = key
    }
}
#endif
