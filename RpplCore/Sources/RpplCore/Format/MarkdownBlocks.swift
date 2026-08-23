import Foundation

/// Coarse Markdown block for rendering legal / docs text in SwiftUI without a full MD engine.
///
/// Handles headings, paragraphs, unordered list items, and thematic breaks (`---`).
/// Inline markup (`**bold**`, links) stays in the block string for the UI layer.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(String)
    case thematicBreak
}

public enum MarkdownBlocks {
    /// Splits CommonMark-ish source into blocks. Preserves blank-line paragraph breaks.
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let trimmed = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            paragraphLines.removeAll(keepingCapacity: true)
            guard !trimmed.isEmpty else { return }
            blocks.append(.paragraph(trimmed.joined(separator: " ")))
        }

        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if isThematicBreak(trimmed) {
                flushParagraph()
                blocks.append(.thematicBreak)
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let item = parseListItem(trimmed) {
                flushParagraph()
                blocks.append(item)
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        return blocks
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
            && Set(compact).count == 1
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        guard line.first == "#" else { return nil }
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0, index < line.endIndex, line[index].isWhitespace else { return nil }
        let text = String(line[index...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: level, text: text)
    }

    private static func parseListItem(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .listItem(text)
    }
}
