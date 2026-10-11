import UIKit

/// Compares the production renderer to the uploaded 23pt/@3x reference,
/// including the continuous tail outline. No synthetic rounded-rectangle oracle.
enum BottomBubblePixelAudit {
    private struct Mask {
        let width: Int, height: Int
        let points: Set<Int>
    }
    private static func mask(_ image: UIImage) -> Mask? {
        let width = 109, height = 85
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let cg = image.cgImage else { return nil }
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var points = Set<Int>()
        let pixelCount = width * height
        for i in 0..<pixelCount {
            let offset = i * 4
            let red = Int(bytes[offset])
            let green = Int(bytes[offset + 1])
            let blue = Int(bytes[offset + 2])
            if red + green + blue < 450 { points.insert(i) }
        }
        return Mask(width: width, height: height, points: points)
    }
    private static func components(_ mask: Mask) -> [Set<Int>] {
        var left = mask.points, result: [Set<Int>] = []
        while let seed = left.first {
            left.remove(seed)
            var todo = [seed], found: Set<Int> = [seed]
            while let p = todo.popLast() {
                let x = p % mask.width, y = p / mask.width
                for (dx, dy) in [(0,1),(0,-1),(1,0),(-1,0)] {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, xx < mask.width, yy >= 0, yy < mask.height else { continue }
                    let n = yy * mask.width + xx
                    if left.remove(n) != nil { todo.append(n); found.insert(n) }
                }
            }
            result.append(found)
        }
        return result.sorted { $0.count > $1.count }
    }
    private static func bounds(_ points: Set<Int>, width: Int) -> CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map { $0 % width }, ys = points.map { $0 / width }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()! + 1, height: ys.max()! - ys.min()! + 1)
    }
    private static func rect(_ value: CGRect) -> [Double] {
        [value.minX, value.minY, value.width, value.height].map(Double.init)
    }
    static func inspect() -> [String: Any] {
        guard let path = Bundle.main.url(forResource: "bubble-outline-590", withExtension: "png"),
              let image = UIImage(contentsOfFile: path.path), let reference = mask(image) else {
            return ["pixelReferenceLoaded": false]
        }
        let expectedOutline = components(reference).first ?? []
        let expectedBox = CGRect(x: 3, y: 3, width: 103, height: 79)
        var minIoU: Double = 1, maxBoxError: CGFloat = 0, sizeError: CGFloat = 0
        var samples: [[String: Any]] = []
        for count in [1,3,23,4] {
            let rendered = CommentBubble.image(count: count, fontSize: 23, color: .black)
            guard let raster = mask(rendered) else { minIoU = 0; continue }
            let parts = components(raster), outline = parts.first ?? []
            let inside = parts.dropFirst().reduce(into: Set<Int>()) { $0.formUnion($1) }
            let box = bounds(outline, width: 109)
            let intersection = outline.intersection(expectedOutline).count
            let union = outline.union(expectedOutline).count
            let iou = Double(intersection) / Double(max(union, 1))
            minIoU = min(minIoU, iou)
            maxBoxError = max(maxBoxError, abs(box.minX - expectedBox.minX), abs(box.minY - expectedBox.minY),
                              abs(box.maxX - expectedBox.maxX), abs(box.maxY - expectedBox.maxY))
            sizeError = max(sizeError, abs(rendered.size.width - 109.0 / 3), abs(rendered.size.height - 85.0 / 3))
            samples.append(["count": count, "outlineIoU": iou, "inkBox": rect(box), "numberBox": rect(bounds(inside, width: 109))])
        }
        return ["pixelReferenceLoaded": true, "bubbleOutlineMinIoU": minIoU,
                "bubbleInkBoxErrorPixels": Double(maxBoxError), "bubbleCanvasSizeError": Double(sizeError),
                "bubblePixelSamples": samples]
    }
}
