import SwiftUI

/// Combined Terms of Use and Privacy Policy — body loaded from bundled `LEGAL.md`.
struct LegalTermsPrivacyView: View {
    private let document = LegalDocument.attributedBody()

    var body: some View {
        ScrollView {
            Text(document)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .textSelection(.enabled)
        }
        .scrollContentBackground(.hidden)
        .background(Color.rpplBackground)
        .navigationTitle("Terms & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.rpplBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Color.rpplAccent)
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

    static func attributedBody() -> AttributedString {
        let source = markdown()
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        if let attributed = try? AttributedString(markdown: source, options: options) {
            return attributed
        }
        return AttributedString(source)
    }
}

#Preview {
    NavigationStack {
        LegalTermsPrivacyView()
    }
}
