import RpplCore
import SwiftUI

/// Combined Terms of Use and Privacy Policy — body loaded from bundled `LEGAL.md`.
struct LegalTermsPrivacyView: View {
    private let blocks: [MarkdownBlock]

    init(markdown: String = LegalDocument.markdown()) {
        blocks = MarkdownBlocks.parse(markdown)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    blockView(block)
                        .padding(.top, topPadding(for: block, at: index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .textSelection(.enabled)
        }
        .scrollContentBackground(.hidden)
        .background(RpplBackdrop())
        .navigationTitle("Terms & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.rpplBackdropTop, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Color.rpplAccent)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inlineAttributed(text))
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .semibold : .medium)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(Self.inlineAttributed(text))
                .font(.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.body)
                Text(Self.inlineAttributed(text))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.primary)
        case .thematicBreak:
            Divider()
                .padding(.vertical, 8)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }

    private func topPadding(for block: MarkdownBlock, at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        switch block {
        case .heading(let level, _) where level <= 2:
            return 20
        case .heading:
            return 14
        case .paragraph:
            return 10
        case .listItem:
            if case .listItem = blocks[index - 1] { return 4 }
            return 10
        case .thematicBreak:
            return 8
        }
    }

    /// Inline Markdown only — keeps newlines out of the equation; blocks own spacing.
    private static func inlineAttributed(_ source: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attributed = try? AttributedString(markdown: source, options: options) {
            return attributed
        }
        return AttributedString(source)
    }
}

/// Loads repo `LEGAL.md` from the app bundle (kept in sync by `scripts/git-hooks/sync-legal-md.sh`).
enum LegalDocument {
    static let resourceName = "LEGAL"

    static func markdown() -> String {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return """
            # Terms & Privacy Policy

            Unable to load this document. Please contact rppl@dcsbl.nl.
            """
    }
}

#Preview {
    NavigationStack {
        LegalTermsPrivacyView()
    }
}
