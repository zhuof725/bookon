import UIKit

/// Conservative edge-connected matte removal, never a global white-pixel key.
/// Already transparent artwork keeps its alpha; complex backgrounds stay intact.
enum ThemeIconTransparency {
    static func image(_ source: CGImage) -> CGImage? {
        let w = source.width, h = source.height
        guard w > 1, h > 1, w <= 2000, h <= 2000 else { return source }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return false }
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        guard drawn else { return nil }
        // Do not disturb existing transparency (including antialiased edges).
        if stride(from: 3, to: bytes.count, by: 4).contains(where: { bytes[$0] < 250 }) { return source }
        let corners = [0, w - 1, (h - 1) * w, w * h - 1]
        let bg = (0..<3).map { c in corners.reduce(0) { $0 + Int(bytes[$1 * 4 + c]) } / 4 }
        func distance(_ p: Int) -> Int { (0..<3).map { abs(Int(bytes[p * 4 + $0]) - bg[$0]) }.max() ?? 255 }
        guard corners.allSatisfy({ distance($0) <= 16 }) else { return source }
        var edges = [Int]()
        for x in 0..<w { edges.append(x); edges.append((h - 1) * w + x) }
        for y in 1..<(h - 1) { edges.append(y * w); edges.append(y * w + w - 1) }
        guard edges.filter({ distance($0) <= 24 }).count * 100 / edges.count >= 92 else { return source }
        var visited = [Bool](repeating: false, count: w * h)
        var queue = [Int](); queue.reserveCapacity(w * h)
        func enqueue(_ p: Int) {
            guard !visited[p] else { return }; visited[p] = true
            if distance(p) <= 40 { queue.append(p) }
        }
        edges.forEach(enqueue)
        var head = 0
        while head < queue.count {
            let p = queue[head]; head += 1
            let x = p % w, y = p / w
            if x > 0 { enqueue(p - 1) }; if x + 1 < w { enqueue(p + 1) }
            if y > 0 { enqueue(p - w) }; if y + 1 < h { enqueue(p + w) }
        }
        // Uniform/blank artwork must not silently turn into an invisible icon.
        guard queue.count < w * h * 98 / 100 else { return source }
        for p in queue {
            let alpha = max(0, min(255, (distance(p) - 16) * 255 / 24))
            for c in 0..<3 { bytes[p * 4 + c] = UInt8(Int(bytes[p * 4 + c]) * alpha / 255) }
            bytes[p * 4 + 3] = UInt8(alpha)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: info),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
