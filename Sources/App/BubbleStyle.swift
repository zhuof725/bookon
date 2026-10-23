import SwiftUI
import UIKit

struct BubbleStyle: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "自定义气泡"
    var mode = "template"
    var template = "bubble"
    var showNumber = true
    var format = "{n}"
    var followText = true
    var colorHex = "#555555"
    var scale = 1.0
    var aspect = 1.0
    var svg = ""
    var imageData: Data?
}

/// One atomic document; draft previews never change the selected runtime style.
final class BubbleStyleStore: ObservableObject {
    nonisolated(unsafe) static let shared = BubbleStyleStore()
    private struct Document: Codable { var styles: [BubbleStyle]; var selectedID: String? }
    private static let key = "reader.bubble.styles.v1"
    @Published private(set) var styles: [BubbleStyle] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var revision = 0
    private let defaults: UserDefaults
    private let runtime: Bool
    init(defaults: UserDefaults = .standard, runtime: Bool = true) {
        self.defaults = defaults; self.runtime = runtime
        if let data = defaults.data(forKey: Self.key), data.count <= 20_000_000,
           let doc = try? JSONDecoder().decode(Document.self, from: data) {
            styles = Array(doc.styles.prefix(30)).filter { Self.validate($0) == nil }
            selectedID = styles.contains { $0.id == doc.selectedID } ? doc.selectedID : nil
        }
        if runtime { BubbleStyleRuntime.set(styles.first { $0.id == selectedID }) }
    }
    static func validate(_ s: BubbleStyle) -> String? {
        if s.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || s.name.count > 40 { return "样式名称须为 1–40 个字符" }
        if !s.scale.isFinite || !(0.6...1.8).contains(s.scale) || !s.aspect.isFinite || !(0.6...2).contains(s.aspect) { return "尺寸超出允许范围" }
        if s.format.count > 16 || s.format.contains("\n") { return "显示格式最多 16 字符且不能换行" }
        if s.colorHex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) == nil { return "颜色格式无效" }
        switch s.mode {
        case "template": if !["bubble", "candy", "square"].contains(s.template) { return "模板无效" }
        case "svg": return BubbleSVG.validate(s.svg)
        case "image":
            guard let data = s.imageData, data.count <= 2_000_000, let image = UIImage(data: data),
                  image.size.width > 0, image.size.height > 0,
                  image.size.width * image.scale <= 1024, image.size.height * image.scale <= 1024 else { return "请选择有效的 PNG 图片（不超过 1024 像素/2 MB）" }
        default: return "创建方式无效"
        }
        return nil
    }
    func save(_ style: BubbleStyle) throws {
        if let error = Self.validate(style) { throw failure(error) }
        var next = styles
        if let i = next.firstIndex(where: { $0.id == style.id }) { next[i] = style }
        else { guard next.count < 30 else { throw failure("最多保存 30 个样式") }; next.append(style) }
        try persist(next, selected: selectedID)
    }
    func select(_ id: String?) throws {
        guard id == nil || styles.contains(where: { $0.id == id }) else { throw failure("样式不存在") }
        try persist(styles, selected: id)
    }
    func delete(_ id: String) throws {
        try persist(styles.filter { $0.id != id }, selected: selectedID == id ? nil : selectedID)
    }
    private func persist(_ next: [BubbleStyle], selected: String?) throws {
        let data = try JSONEncoder().encode(Document(styles: next, selectedID: selected))
        guard data.count <= 20_000_000 else { throw failure("气泡样式总容量不能超过 20 MB") }
        defaults.set(data, forKey: Self.key)
        styles = next; selectedID = selected
        if runtime { BubbleStyleRuntime.set(next.first { $0.id == selected }) }
        revision += 1
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "BubbleStyle", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

/// Layout and prepagination may run off-main; runtime snapshots are lock protected.
enum BubbleStyleRuntime {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var selected: BubbleStyle?
    private nonisolated(unsafe) static var version = 0
    static var revision: Int { lock.lock(); defer { lock.unlock() }; return version }
    static func set(_ style: BubbleStyle?) { lock.lock(); selected = style; version += 1; lock.unlock() }
    static func snapshot() -> BubbleStyle? { lock.lock(); defer { lock.unlock() }; return selected }
}

enum BubbleStyleRenderer {
    static func bounds(style: BubbleStyle, fontSize: CGFloat) -> CGRect {
        let s = max(fontSize, 1) / 23 * CGFloat(style.scale)
        return CGRect(x: 0, y: -4 * s, width: 109 / 3 * s * CGFloat(style.aspect), height: 85 / 3 * s)
    }
    static func image(style: BubbleStyle, count: Int, fontSize: CGFloat, color: UIColor) -> UIImage {
        let size = bounds(style: style, fontSize: fontSize).size
        let format = UIGraphicsImageRendererFormat(); format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let ink = style.followText ? color : hex(style.colorHex)
            if style.mode == "image", let data = style.imageData, let image = UIImage(data: data) {
                image.draw(in: rect)
            } else if style.mode == "svg" {
                BubbleSVG.draw(style.svg, in: rect, color: ink)
            } else {
                let body = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.09)
                let path = UIBezierPath(roundedRect: body, cornerRadius: style.template == "square" ? 3 : body.height * 0.42)
                if style.template == "candy" {
                    UIColor.white.setFill(); path.fill(); UIColor.black.setStroke()
                    for x in [rect.minX, body.maxX] {
                        let wing = UIBezierPath(); wing.move(to: CGPoint(x: x, y: body.midY - 4))
                        wing.addLine(to: CGPoint(x: x + rect.width * 0.08, y: body.midY))
                        wing.addLine(to: CGPoint(x: x, y: body.midY + 4)); wing.close()
                        UIColor.white.setFill(); wing.fill(); wing.lineWidth = 0.8; wing.stroke()
                    }
                } else { ink.setStroke() }
                path.lineWidth = max(0.8, size.height / 28); path.stroke()
                if style.template != "candy" {
                    let tail = UIBezierPath(); tail.move(to: CGPoint(x: body.minX + 5, y: body.maxY - 2))
                    tail.addLine(to: CGPoint(x: body.minX + 1, y: rect.maxY))
                    tail.addLine(to: CGPoint(x: body.minX + 12, y: body.maxY)); tail.lineWidth = path.lineWidth; tail.stroke()
                }
            }
            if style.showNumber {
                let label = style.format.replacingOccurrences(of: "{n}", with: String(max(0, count)))
                let textColor = style.mode == "template" && style.template == "candy" ? UIColor.darkGray : ink
                var fontSize = size.height * 0.38
                let maxWidth = size.width * 0.74
                var attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: textColor]
                let width = (label as NSString).size(withAttributes: attrs).width
                if width > maxWidth { fontSize *= maxWidth / max(width, 1); attrs[.font] = UIFont.systemFont(ofSize: fontSize, weight: .semibold) }
                let measured = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(at: CGPoint(x: (size.width - measured.width) / 2, y: (size.height - measured.height) / 2 - 1), withAttributes: attrs)
            }
        }.withRenderingMode(.alwaysOriginal)
    }
    static func hex(_ value: String) -> UIColor {
        let n = UInt32(value.dropFirst(), radix: 16) ?? 0x555555
        return UIColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
}
