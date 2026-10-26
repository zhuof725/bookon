import Foundation

/// 章节标题样式：解析一小段 CSS（`font-size: 20px; color: #333; border-bottom: 1px solid #eee`）。
///
/// 只认识阅读器真正会用到的属性，其余声明直接忽略；写错的部分退回默认样式，
/// 所以空串 = 现在的外观。支持的属性：
/// `font-size / font-weight / font-style / color / background(-color) /
/// text-align / letter-spacing / line-height / text-decoration / text-transform /
/// opacity / margin(-top/-bottom) / padding(-top/-bottom/-left/-right) /
/// border-bottom(-width/-color)`，单位支持 px / pt / em / rem / %。
struct ChapterTitleStyle: Equatable {
    struct Color: Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        static let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)

        static func parse(_ raw: String) -> Color? {
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !text.isEmpty else { return nil }
            if text == "transparent" || text == "none" { return .clear }
            if let named = namedColors[text] { return named }
            if text.hasPrefix("#") {
                let hex = String(text.dropFirst())
                let digits = Array(hex)
                guard digits.allSatisfy({ $0.isHexDigit }) else { return nil }
                func value(_ chars: [Character]) -> Double {
                    Double(Int(String(chars), radix: 16) ?? 0)
                }
                switch digits.count {
                case 3, 4:
                    let r = value([digits[0], digits[0]]) / 255
                    let g = value([digits[1], digits[1]]) / 255
                    let b = value([digits[2], digits[2]]) / 255
                    let a = digits.count == 4 ? value([digits[3], digits[3]]) / 255 : 1
                    return Color(red: r, green: g, blue: b, alpha: a)
                case 6, 8:
                    let r = value(Array(digits[0...1])) / 255
                    let g = value(Array(digits[2...3])) / 255
                    let b = value(Array(digits[4...5])) / 255
                    let a = digits.count == 8 ? value(Array(digits[6...7])) / 255 : 1
                    return Color(red: r, green: g, blue: b, alpha: a)
                default:
                    return nil
                }
            }
            if text.hasPrefix("rgb") {
                guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") else { return nil }
                let body = text[text.index(after: open)..<close]
                let parts = body
                    .replacingOccurrences(of: "/", with: ",")
                    .split(whereSeparator: { $0 == "," || $0 == " " })
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard parts.count >= 3 else { return nil }
                func channel(_ s: String) -> Double? {
                    if s.hasSuffix("%") { return (Double(s.dropLast()) ?? 0) / 100 }
                    return (Double(s) ?? 0) / 255
                }
                guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
                var a = 1.0
                if parts.count >= 4 {
                    a = parts[3].hasSuffix("%") ? (Double(parts[3].dropLast()) ?? 100) / 100 : (Double(parts[3]) ?? 1)
                }
                return Color(red: r, green: g, blue: b, alpha: min(max(a, 0), 1))
            }
            // currentColor / inherit 这类：跟随主题，不覆盖。
            return nil
        }

        private static let namedColors: [String: Color] = {
            var table: [String: Color] = [:]
            func add(_ name: String, _ r: Int, _ g: Int, _ b: Int) {
                table[name] = Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: 1)
            }
            add("black", 0, 0, 0)
            add("white", 255, 255, 255)
            add("gray", 128, 128, 128)
            add("grey", 128, 128, 128)
            add("silver", 192, 192, 192)
            add("red", 255, 0, 0)
            add("green", 0, 128, 0)
            add("blue", 0, 0, 255)
            add("yellow", 255, 255, 0)
            add("orange", 255, 165, 0)
            add("purple", 128, 0, 128)
            add("brown", 165, 42, 42)
            add("pink", 255, 192, 203)
            add("teal", 0, 128, 128)
            add("navy", 0, 0, 128)
            add("gold", 255, 215, 0)
            return table
        }()
    }

    enum Alignment: String, Equatable {
        case left, center, right, justify
    }

    enum Transform: String, Equatable {
        case none, uppercase, lowercase, capitalize
    }

    var fontSize: Double?
    /// em / rem / % 换算出来的相对倍数（相对默认标题字号）。
    var fontScale: Double?
    var fontWeight: Int?
    var italic: Bool?
    var color: Color?
    var background: Color?
    var alignment: Alignment?
    var letterSpacing: Double?
    /// 行高倍数（1.5 = 1.5 倍字高）。
    var lineHeight: Double?
    var underline: Bool?
    var strikethrough: Bool?
    var transform: Transform?
    var opacity: Double?
    var paddingTop: Double?
    var paddingBottom: Double?
    var paddingHorizontal: Double?
    var marginTop: Double?
    var marginBottom: Double?
    var borderBottomWidth: Double?
    var borderBottomColor: Color?

    static let empty = ChapterTitleStyle()

    var isEmpty: Bool { self == ChapterTitleStyle() }

    var hasBorder: Bool { (borderBottomWidth ?? 0) > 0 }

    // MARK: 解析

    static func parse(_ css: String) -> ChapterTitleStyle {
        var style = ChapterTitleStyle()
        for (key, value) in declarations(css) {
            switch key {
            case "font-size":
                if let length = length(value) {
                    if length.relative { style.fontScale = length.value } else { style.fontSize = length.value }
                }
            case "font-weight":
                if let weight = fontWeight(value) { style.fontWeight = weight }
            case "font-style":
                if value.hasPrefix("italic") || value.hasPrefix("oblique") { style.italic = true }
                else if value.hasPrefix("normal") { style.italic = false }
            case "color":
                style.color = Color.parse(value)
            case "background", "background-color":
                // `background: #000 url(x) no-repeat` 这类简写只取颜色部分。
                style.background = Color.parse(value)
                    ?? value.split(whereSeparator: { $0 == " " }).compactMap { Color.parse(String($0)) }.first
            case "text-align":
                style.alignment = Alignment(rawValue: value)
            case "letter-spacing":
                if let length = length(value), !length.relative { style.letterSpacing = length.value }
            case "line-height":
                if let scale = lineHeight(value) { style.lineHeight = scale }
            case "text-decoration", "text-decoration-line":
                let lowered = value.lowercased()
                if lowered.contains("underline") { style.underline = true }
                if lowered.contains("line-through") { style.strikethrough = true }
                if lowered.contains("none") { style.underline = false; style.strikethrough = false }
            case "text-transform":
                style.transform = Transform(rawValue: value.lowercased())
            case "opacity":
                if let number = Double(value.components(separatedBy: " ").first ?? "") {
                    style.opacity = min(max(number, 0), 1)
                }
            case "padding":
                if let box = boxValues(value) {
                    style.paddingTop = box.top
                    style.paddingBottom = box.bottom
                    style.paddingHorizontal = box.horizontal
                }
            case "padding-top":
                if let length = length(value), !length.relative { style.paddingTop = length.value }
            case "padding-bottom":
                if let length = length(value), !length.relative { style.paddingBottom = length.value }
            case "padding-left", "padding-right", "padding-inline", "padding-inline-start", "padding-inline-end":
                if let length = length(value), !length.relative { style.paddingHorizontal = length.value }
            case "margin":
                if let box = boxValues(value) {
                    style.marginTop = box.top
                    style.marginBottom = box.bottom
                }
            case "margin-top":
                if let length = length(value), !length.relative { style.marginTop = length.value }
            case "margin-bottom":
                if let length = length(value), !length.relative { style.marginBottom = length.value }
            case "border-bottom-width":
                if let length = length(value), !length.relative { style.borderBottomWidth = length.value }
            case "border-bottom-color":
                style.borderBottomColor = Color.parse(value)
            case "border-bottom", "border":
                let parts = value.split(whereSeparator: { $0 == " " }).map(String.init)
                for part in parts {
                    if let length = length(part), !length.relative, length.value > 0 {
                        style.borderBottomWidth = length.value
                    } else if let color = Color.parse(part) {
                        style.borderBottomColor = color
                    }
                }
            case "border-bottom-style", "border-style":
                if value.contains("none") && !value.contains("solid") { style.borderBottomWidth = 0 }
                if style.borderBottomWidth == nil, !value.contains("none") { style.borderBottomWidth = 1 }
            default:
                continue
            }
        }
        return style
    }

    /// 拆成 `属性: 值` 列表。
    ///
    /// 支持直接粘一段带选择器的 CSS（`.chapter-title { color: #fff; background: #000 }`）：
    /// 只取花括号里的声明；没有花括号就整段当声明列表。
    /// 顺便去掉注释、`!important`，并把中文输入法打出来的全角冒号/分号归一化。
    static func declarations(_ css: String) -> [(String, String)] {
        var text = css
        while let start = text.range(of: "/*"), let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        text = text
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "；", with: ";")
        if text.contains("{") {
            var extracted = ""
            for block in text.split(separator: "{").dropFirst() {
                if let body = block.split(separator: "}").first { extracted += body + ";" }
            }
            if !extracted.isEmpty { text = extracted }
        } else {
            text = text.replacingOccurrences(of: "}", with: "")
        }
        var out: [(String, String)] = []
        for chunk in text.split(separator: ";") {
            guard let colon = chunk.firstIndex(of: ":") else { continue }
            let key = chunk[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = chunk[chunk.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let important = value.range(of: "!important", options: .caseInsensitive) {
                value.removeSubrange(important)
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !key.isEmpty, !value.isEmpty, !key.contains(" "), !key.contains("{") else { continue }
            out.append((key, value.lowercased()))
        }
        return out
    }

    /// `8px` → 绝对长度；`1.2em` / `120%` → 相对倍数。
    static func length(_ raw: String) -> (value: Double, relative: Bool)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = text.first, first.isNumber || first == "." || first == "-" || first == "+" else { return nil }
        var number = ""
        while let c = text.first, c.isNumber || c == "." || c == "-" || c == "+" {
            number.append(c)
            text.removeFirst()
        }
        guard let value = Double(number) else { return nil }
        let unit = text.trimmingCharacters(in: .whitespaces)
        switch unit {
        case "", "px", "pt", "dp":
            return (value, false)
        case "em", "rem":
            return (value, true)
        case "%":
            return (value / 100, true)
        case "vw", "vh":
            return (value / 100, true)
        default:
            return nil
        }
    }

    static func fontWeight(_ raw: String) -> Int? {
        switch raw.trimmingCharacters(in: .whitespaces) {
        case "normal": return 400
        case "bold", "bolder": return 700
        case "lighter": return 300
        default:
            guard let number = Int(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
            return min(max(number, 100), 900)
        }
    }

    /// 行高：`1.5` 或 `150%` 都按倍数处理；带单位的按「相对字号的倍数」近似（需要字号，交给调用方）。
    static func lineHeight(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("%") { return (Double(text.dropLast()) ?? 0) / 100 }
        return Double(text)
    }

    /// CSS 的 1~4 值简写：上 / 左右 / 下。
    static func boxValues(_ raw: String) -> (top: Double, bottom: Double, horizontal: Double?)? {
        let parts = raw.split(whereSeparator: { $0 == " " }).map(String.init).filter { !$0.isEmpty }
        let values = parts.compactMap { length($0) }.filter { !$0.relative }.map(\.value)
        guard !values.isEmpty else { return nil }
        switch values.count {
        case 1:
            return (values[0], values[0], values[0])
        case 2:
            return (values[0], values[0], values[1])
        default:
            return (values[0], values.count >= 3 ? values[2] : values[0], values[1])
        }
    }
}
