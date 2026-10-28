import SwiftUI
import RpplCore

enum RecordingIssueText {
    /// Short label for a badge; unknown codes fall back to a generic line (codes are opaque).
    static func label(for code: String) -> LocalizedStringKey {
        switch code {
        case RecordingHealth.Code.hkMissing: "Screen-on only"
        case RecordingHealth.Code.writeFailing: "Save failing"
        case RecordingHealth.Code.storageLow: "Storage low"
        case RecordingHealth.Code.gpsMissing: "No GPS"
        case RecordingHealth.Code.batteryLow: "Battery low"
        case RecordingHealth.Code.locationReduced: "Approximate location"
        default: "Recording at risk"
        }
    }
}

/// Worst current issue as a capsule, with a count when there are more. Fixed height so the
/// layout does not jump; renders nothing when the recording is healthy.
struct RecordingIssueBadge: View {
    let issues: [RecordingIssue]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let worst = issues.first {
            HStack(spacing: 3) {
                // At accessibility sizes the text would cover the page: a symbol says "at risk", the
                // controls page still names the issue.
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "exclamationmark.triangle.fill")
                } else {
                    Text(RecordingIssueText.label(for: worst.code))
                }
                if issues.count > 1 {
                    Text("+\(issues.count - 1)")
                }
            }
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(worst.severity == .critical ? Color.red : Color.orange, in: Capsule())
            .foregroundStyle(.black)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(RecordingIssueText.label(for: worst.code)))
            .allowsHitTesting(false)
        }
    }
}
