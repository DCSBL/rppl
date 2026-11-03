import Foundation

/// A small, forgiving HTML reader: enough to pull readable text, headings and links out of a park
/// website. It is not a browser and never runs scripts.
enum ParkHTML {
    enum Token: Equatable {
        case text(String)
        case open(name: String, attributes: [String: String])
        case close(name: String)
    }

    /// Elements whose content is never text for a person.
    private static let hidden: Set<String> = [
        "script", "style", "noscript", "svg", "template", "iframe", "canvas", "select", "button",
    ]

    static func tokens(_ html: String) -> [Token] {
        let chars = Array(html)
        var tokens: [Token] = []
        var text = ""
        var index = 0

        func flush() {
            if !text.isEmpty {
                tokens.append(.text(text))
                text = ""
            }
        }

        while index < chars.count {
            let char = chars[index]
            guard char == "<" else {
                text.append(char)
                index += 1
                continue
            }
            if matches("<!--", at: index, in: chars) {
                index = indexAfter("-->", from: index + 4, in: chars) ?? chars.count
                continue
            }
            if index + 1 < chars.count, chars[index + 1] == "!" || chars[index + 1] == "?" {
                index = indexAfter(">", from: index + 2, in: chars) ?? chars.count
                continue
            }
            let closing = index + 1 < chars.count && chars[index + 1] == "/"
            let nameStart = closing ? index + 2 : index + 1
            guard nameStart < chars.count, chars[nameStart].isASCII, chars[nameStart].isLetter else {
                text.append(char)
                index += 1
                continue
            }
            var cursor = nameStart
            while cursor < chars.count, !chars[cursor].isWhitespace, chars[cursor] != ">", chars[cursor] != "/" {
                cursor += 1
            }
            let name = String(chars[nameStart..<cursor]).lowercased()
            var attributes: [String: String] = [:]
            while cursor < chars.count, chars[cursor] != ">" {
                if chars[cursor].isWhitespace || chars[cursor] == "/" {
                    cursor += 1
                    continue
                }
                var keyEnd = cursor
                while keyEnd < chars.count, !chars[keyEnd].isWhitespace, chars[keyEnd] != "=",
                      chars[keyEnd] != ">", chars[keyEnd] != "/" {
                    keyEnd += 1
                }
                let key = String(chars[cursor..<keyEnd]).lowercased()
                cursor = keyEnd
                while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
                var value = ""
                if cursor < chars.count, chars[cursor] == "=" {
                    cursor += 1
                    while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
                    if cursor < chars.count, chars[cursor] == "\"" || chars[cursor] == "'" {
                        let quote = chars[cursor]
                        cursor += 1
                        var valueEnd = cursor
                        while valueEnd < chars.count, chars[valueEnd] != quote { valueEnd += 1 }
                        value = String(chars[cursor..<valueEnd])
                        cursor = min(valueEnd + 1, chars.count)
                    } else {
                        var valueEnd = cursor
                        while valueEnd < chars.count, !chars[valueEnd].isWhitespace, chars[valueEnd] != ">" {
                            valueEnd += 1
                        }
                        value = String(chars[cursor..<valueEnd])
                        cursor = valueEnd
                    }
                }
                if !key.isEmpty { attributes[key] = decode(value) }
            }
            index = min(cursor + 1, chars.count)
            flush()
            if closing {
                tokens.append(.close(name: name))
                continue
            }
            tokens.append(.open(name: name, attributes: attributes))
            if hidden.contains(name) {
                let end = indexOfClosingTag(name, from: index, in: chars)
                index = indexAfter(">", from: end, in: chars) ?? chars.count
                tokens.append(.close(name: name))
            }
        }
        flush()
        return tokens
    }

    // MARK: Entities

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "euro": "€",
        "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©", "middot": "·", "bull": "•",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "agrave": "à", "ccedil": "ç",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") {
                let name = String(text[text.index(after: index)..<semicolon])
                if let replacement = replacement(for: name) {
                    result += replacement
                    index = text.index(after: semicolon)
                    continue
                }
            }
            result.append(char)
            index = text.index(after: index)
        }
        return result
    }

    private static func replacement(for name: String) -> String? {
        if name.hasPrefix("#") {
            let body = name.dropFirst()
            let value: UInt32?
            if body.lowercased().hasPrefix("x") {
                value = UInt32(body.dropFirst(), radix: 16)
            } else {
                value = UInt32(body)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return named[name]
    }

    // MARK: Scanning

    private static func matches(_ pattern: String, at index: Int, in chars: [Character]) -> Bool {
        let pattern = Array(pattern)
        guard index + pattern.count <= chars.count else { return false }
        for offset in 0..<pattern.count where chars[index + offset] != pattern[offset] { return false }
        return true
    }

    /// The index just after the first `pattern` at or after `from`.
    private static func indexAfter(_ pattern: String, from: Int, in chars: [Character]) -> Int? {
        let pattern = Array(pattern)
        guard !pattern.isEmpty else { return nil }
        var index = max(from, 0)
        while index + pattern.count <= chars.count {
            var found = true
            for offset in 0..<pattern.count where chars[index + offset] != pattern[offset] {
                found = false
                break
            }
            if found { return index + pattern.count }
            index += 1
        }
        return nil
    }

    /// The index of the `<` of the next `</name`, any casing; the end of the text when there is none.
    private static func indexOfClosingTag(_ name: String, from: Int, in chars: [Character]) -> Int {
        let pattern = Array("</" + name)
        var index = max(from, 0)
        while index + pattern.count <= chars.count {
            var found = true
            for offset in 0..<pattern.count where chars[index + offset].lowercased() != String(pattern[offset]) {
                found = false
                break
            }
            if found { return index }
            index += 1
        }
        return chars.count
    }
}
