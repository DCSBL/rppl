import SwiftUI

/// Pictogrammers Material Design Icons (Apache License 2.0).
/// Add more by pasting the 24×24 SVG `d` from https://pictogrammers.com/library/mdi/
enum MDIIcon: String, CaseIterable {
    case skiWater = "ski-water"

    var accessibilityLabel: String {
        switch self {
        case .skiWater:
            return String(localized: "Wakeboarding")
        }
    }

    var svgPath: String {
        switch self {
        case .skiWater:
            return "M4.2 3.5C4.2 2.7 4.9 1.9 5.8 1.9C6.7 1.9 7.4 2.6 7.4 3.5S6.6 5 5.8 5 4.2 4.3 4.2 3.5M22 3.9L21.5 3L13.5 7.1L14 8L22 3.9M20.8 20.3L21.7 21.2C21.1 21.8 20.5 22.2 19.8 22.5S18.3 23 17.5 23H2V21.7H4.7L6.8 18.2L4.5 15L3.7 7.2C3.7 6.3 4.5 5.5 5.4 5.5C5.7 5.5 6 5.6 6.2 5.7L9.7 8.3L12 7.5L12.8 9.1L9.3 10.6C9.2 10.5 7.7 9.4 6.6 8.5L7 12L12.3 16.5L14 21.7H17.5C18.1 21.7 18.7 21.6 19.3 21.3C19.9 21.1 20.4 20.7 20.8 20.3M7 21.7H12L10.4 17.8L8.1 15.9L9.3 18.4L7 21.7Z"
        }
    }
}

struct MDIIconView: View {
    var icon: MDIIcon

    var body: some View {
        SVGPathShape(d: icon.svgPath)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel(icon.accessibilityLabel)
    }
}

/// Renders a 24×24 Material Design Icons SVG path.
struct SVGPathShape: Shape {
    var d: String
    var viewBoxSize: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let built = SVGPathBuilder.path(from: d)
        let transform = CGAffineTransform(
            a: rect.width / viewBoxSize,
            b: 0,
            c: 0,
            d: rect.height / viewBoxSize,
            tx: rect.minX,
            ty: rect.minY
        )
        return built.applying(transform)
    }
}

enum SVGPathBuilder {
    static func path(from d: String) -> Path {
        var path = Path()
        let tokens = tokenize(d)
        var index = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastCommand: Character = "M"

        func remaining() -> Int { tokens.count - index }

        func takeCommand() -> Character? {
            guard index < tokens.count else { return nil }
            if case .command(let command) = tokens[index] {
                index += 1
                return command
            }
            if lastCommand == "Z" || lastCommand == "z" {
                return nil
            }
            let implicit: Character
            switch lastCommand {
            case "M": implicit = "L"
            case "m": implicit = "l"
            default: implicit = lastCommand
            }
            return implicit
        }

        func takeNumbers(_ count: Int) -> [CGFloat]? {
            guard remaining() >= count else { return nil }
            var values: [CGFloat] = []
            values.reserveCapacity(count)
            for offset in 0..<count {
                guard case .number(let value) = tokens[index + offset] else { return nil }
                values.append(value)
            }
            index += count
            return values
        }

        func point(_ x: CGFloat, _ y: CGFloat, relative: Bool) -> CGPoint {
            if relative {
                return CGPoint(x: current.x + x, y: current.y + y)
            }
            return CGPoint(x: x, y: y)
        }

        func reflectedCubicControl() -> CGPoint {
            guard let lastCubicControl else { return current }
            return CGPoint(
                x: 2 * current.x - lastCubicControl.x,
                y: 2 * current.y - lastCubicControl.y
            )
        }

        while index < tokens.count {
            guard let command = takeCommand() else { break }
            let relative = command.isLowercase
            lastCommand = command

            switch command {
            case "M", "m":
                guard let values = takeNumbers(2) else { return path }
                current = point(values[0], values[1], relative: relative)
                subpathStart = current
                path.move(to: current)
                lastCubicControl = nil
                while let extra = takeNumbers(2) {
                    current = point(extra[0], extra[1], relative: relative)
                    path.addLine(to: current)
                }

            case "L", "l":
                while let values = takeNumbers(2) {
                    current = point(values[0], values[1], relative: relative)
                    path.addLine(to: current)
                    lastCubicControl = nil
                }

            case "H", "h":
                while let values = takeNumbers(1) {
                    let x = relative ? current.x + values[0] : values[0]
                    current = CGPoint(x: x, y: current.y)
                    path.addLine(to: current)
                    lastCubicControl = nil
                }

            case "V", "v":
                while let values = takeNumbers(1) {
                    let y = relative ? current.y + values[0] : values[0]
                    current = CGPoint(x: current.x, y: y)
                    path.addLine(to: current)
                    lastCubicControl = nil
                }

            case "C", "c":
                while let values = takeNumbers(6) {
                    let control1 = point(values[0], values[1], relative: relative)
                    let control2 = point(values[2], values[3], relative: relative)
                    current = point(values[4], values[5], relative: relative)
                    path.addCurve(to: current, control1: control1, control2: control2)
                    lastCubicControl = control2
                }

            case "S", "s":
                while let values = takeNumbers(4) {
                    let control1 = reflectedCubicControl()
                    let control2 = point(values[0], values[1], relative: relative)
                    current = point(values[2], values[3], relative: relative)
                    path.addCurve(to: current, control1: control1, control2: control2)
                    lastCubicControl = control2
                }

            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
                lastCubicControl = nil

            default:
                while index < tokens.count {
                    if case .number = tokens[index] {
                        index += 1
                    } else {
                        break
                    }
                }
            }
        }

        return path
    }

    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char.isWhitespace || char == "," {
                index += 1
                continue
            }
            if char.isLetter {
                tokens.append(.command(char))
                index += 1
                continue
            }
            let (value, next) = parseNumber(chars, at: index)
            tokens.append(.number(value))
            index = next
        }
        return tokens
    }

    private static func parseNumber(_ chars: [Character], at start: Int) -> (CGFloat, Int) {
        var index = start
        if index < chars.count, chars[index] == "+" || chars[index] == "-" {
            index += 1
        }
        while index < chars.count, chars[index].isNumber {
            index += 1
        }
        if index < chars.count, chars[index] == "." {
            index += 1
            while index < chars.count, chars[index].isNumber {
                index += 1
            }
        }
        if index < chars.count, chars[index] == "e" || chars[index] == "E" {
            index += 1
            if index < chars.count, chars[index] == "+" || chars[index] == "-" {
                index += 1
            }
            while index < chars.count, chars[index].isNumber {
                index += 1
            }
        }
        let text = String(chars[start..<index])
        return (CGFloat(Double(text) ?? 0), max(index, start + 1))
    }
}
