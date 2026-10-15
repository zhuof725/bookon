import UIKit
import Foundation

/// Static vector backgrounds only: no WebKit, scripts, network, entities or embedded images.
enum BubbleSVG {
    static func validate(_ svg: String) -> String? { parse(svg).error }
    private static func parse(_ svg: String) -> Parser {
        let delegate = Parser()
        guard svg.utf8.count <= 32_768, !svg.isEmpty,
              !svg.contains("<!"), !svg.contains("<?") else {
            delegate.error = "SVG 须小于 32 KB，且不能包含声明、实体或脚本"; return delegate
        }
        let parser = XMLParser(data: Data(svg.utf8)); parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        if !parser.parse(), delegate.error == nil { delegate.error = "SVG XML 格式无效" }
        if delegate.viewBox == nil { delegate.error = "请提供有效的 SVG viewBox" }
        return delegate
    }
    static func draw(_ svg: String, in rect: CGRect, color: UIColor) {
        let parsed = parse(svg)
        guard parsed.error == nil, let box = parsed.viewBox, let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.clip(to: rect); ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / box.width, y: rect.height / box.height)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        for shape in parsed.shapes {
            ctx.saveGState(); ctx.setAlpha(shape.opacity)
            if let fill = paint(shape.fill, current: color) {
                ctx.addPath(shape.path.cgPath); ctx.setFillColor(fill.cgColor); ctx.drawPath(using: .fill)
            }
            if let stroke = paint(shape.stroke, current: color) {
                ctx.addPath(shape.path.cgPath); ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(shape.width); ctx.strokePath()
            }
            ctx.restoreGState()
        }
    }
    private static func paint(_ value: String, current: UIColor) -> UIColor? {
        switch value { case "none": return nil; case "currentColor": return current
        case "black": return .black; case "white": return .white; case "red": return .red
        case "gray": return .gray; default: return BubbleStyleRenderer.hex(value) }
    }
    private struct Shape { var path: UIBezierPath; var fill: String; var stroke: String; var width: CGFloat; var opacity: CGFloat }
    private final class Parser: NSObject, XMLParserDelegate {
        var error: String?
        var viewBox: CGRect?
        var shapes: [Shape] = []
        var depth = 0
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            guard error == nil else { parser.abortParsing(); return }
            depth += 1
            guard depth <= 2, shapes.count < 128 else { fail(parser, "SVG 最多 128 个图形，仅支持根节点下的静态图形"); return }
            let allowed: [String: Set<String>] = [
                "svg": ["xmlns", "viewBox", "width", "height"],
                "rect": ["x", "y", "width", "height", "rx"], "circle": ["cx", "cy", "r"],
                "ellipse": ["cx", "cy", "rx", "ry"], "line": ["x1", "y1", "x2", "y2"],
                "polygon": ["points"], "polyline": ["points"], "path": ["d"]]
            guard let attrs = allowed[name], (depth == 1) == (name == "svg") else { fail(parser, "不支持 SVG 元素：\(name)"); return }
            let style: Set<String> = name == "svg" ? [] : ["fill", "stroke", "stroke-width", "opacity"]
            guard Set(a.keys).isSubset(of: attrs.union(style)) else { fail(parser, "SVG 含未支持属性（不支持样式表、变换或外链）"); return }
            func number(_ key: String, _ fallback: CGFloat = 0) -> CGFloat {
                guard let raw = a[key] else { return fallback }
                guard let n = Double(raw), n.isFinite, abs(n) <= 10000 else { self.error = "SVG 数值无效"; return 0 }
                return CGFloat(n)
            }
            if name == "svg" {
                let nums = Self.numbers(a["viewBox"] ?? "0 0 \(a["width"] ?? "") \(a["height"] ?? "")")
                guard let n = nums, n.count == 4, n[2] > 0, n[3] > 0 else { fail(parser, "SVG 需要有效 viewBox 或宽高"); return }
                viewBox = CGRect(x: n[0], y: n[1], width: n[2], height: n[3]); return
            }
            let fill = a["fill"] ?? "black", stroke = a["stroke"] ?? "none"
            for value in [fill, stroke] {
                if !["none", "currentColor", "black", "white", "red", "gray"].contains(value), value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) == nil { fail(parser, "SVG 颜色请用 #RRGGBB、currentColor 或基本颜色名"); return }
            }
            var path = UIBezierPath()
            switch name {
            case "rect":
                let w = number("width"), h = number("height")
                guard w > 0, h > 0 else { fail(parser, "矩形宽高须大于零"); return }
                path = UIBezierPath(roundedRect: CGRect(x: number("x"), y: number("y"), width: w, height: h), cornerRadius: max(0, number("rx")))
            case "circle", "ellipse":
                let rx = number(name == "circle" ? "r" : "rx"), ry = number(name == "circle" ? "r" : "ry")
                guard rx > 0, ry > 0 else { fail(parser, "圆半径须大于零"); return }
                path = UIBezierPath(ovalIn: CGRect(x: number("cx") - rx, y: number("cy") - ry, width: 2 * rx, height: 2 * ry))
            case "line": path.move(to: CGPoint(x: number("x1"), y: number("y1"))); path.addLine(to: CGPoint(x: number("x2"), y: number("y2")))
            case "polygon", "polyline":
                guard let n = Self.numbers(a["points"] ?? ""), n.count >= 4, n.count % 2 == 0 else { fail(parser, "SVG points 无效"); return }
                path.move(to: CGPoint(x: n[0], y: n[1]))
                for i in stride(from: 2, to: n.count, by: 2) { path.addLine(to: CGPoint(x: n[i], y: n[i + 1])) }
                if name == "polygon" { path.close() }
            case "path":
                guard let result = BubbleSVG.path(a["d"] ?? "") else { fail(parser, "路径仅支持 M/L/H/V/C/Q/Z 命令，请展开其他命令后导入"); return }; path = result
            default: break
            }
            let width = number("stroke-width", 1), opacity = number("opacity", 1)
            guard error == nil, width >= 0, (0...1).contains(opacity) else { fail(parser, "SVG 线宽或透明度无效"); return }
            shapes.append(Shape(path: path, fill: fill, stroke: stroke, width: width, opacity: opacity))
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1 }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail(parser, "SVG 背景不支持文字，数字请使用下方显示格式") }
        }
        private func fail(_ parser: XMLParser, _ text: String) { error = text; parser.abortParsing() }
        static func numbers(_ text: String) -> [CGFloat]? {
            let parts = text.split { $0.isWhitespace || $0 == "," }
            guard parts.count <= 2048 else { return nil }
            var values: [CGFloat] = []
            for p in parts { guard let n = Double(p), n.isFinite, abs(n) <= 10000 else { return nil }; values.append(CGFloat(n)) }
            return values
        }
    }
    private static func path(_ text: String) -> UIBezierPath? {
        guard let re = try? NSRegularExpression(pattern: "[MmLlHhVvCcQqZz]|[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?[0-9]*)(?:[eE][-+]?[0-9]+)?") else { return nil }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count <= 2048 else { return nil }
        var end = 0, tokens: [String] = []
        for m in matches {
            let gap = ns.substring(with: NSRange(location: end, length: m.range.location - end))
            guard gap.allSatisfy({ $0.isWhitespace || $0 == "," }) else { return nil }
            tokens.append(ns.substring(with: m.range)); end = m.range.location + m.range.length
        }
        guard ns.substring(from: end).allSatisfy({ $0.isWhitespace || $0 == "," }), tokens.first?.uppercased() == "M" else { return nil }
        let p = UIBezierPath(); var i = 0, command = "", point = CGPoint.zero, start = CGPoint.zero
        while i < tokens.count {
            if tokens[i].first?.isLetter == true { command = tokens[i]; i += 1 }
            let upper = command.uppercased(), relative = command != upper
            if upper == "Z" { p.close(); point = start; command = ""; continue }
            let sizes = ["M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "Q": 4]
            guard let count = sizes[upper], i + count <= tokens.count else { return nil }
            var n: [CGFloat] = []
            for k in 0..<count { guard let v = Double(tokens[i + k]), v.isFinite, abs(v) <= 10000 else { return nil }; n.append(CGFloat(v)) }
            i += count
            func xy(_ k: Int) -> CGPoint { CGPoint(x: n[k] + (relative ? point.x : 0), y: n[k + 1] + (relative ? point.y : 0)) }
            switch upper {
            case "M": point = xy(0); start = point; p.move(to: point); command = relative ? "l" : "L"
            case "L": point = xy(0); p.addLine(to: point)
            case "H": point.x = n[0] + (relative ? point.x : 0); p.addLine(to: point)
            case "V": point.y = n[0] + (relative ? point.y : 0); p.addLine(to: point)
            case "C": let a = xy(0), b = xy(2), c = xy(4); p.addCurve(to: c, controlPoint1: a, controlPoint2: b); point = c
            case "Q": let a = xy(0), b = xy(2); p.addQuadCurve(to: b, controlPoint: a); point = b
            default: return nil
            }
            guard abs(point.x) <= 10000, abs(point.y) <= 10000 else { return nil }
        }
        return p
    }
}
