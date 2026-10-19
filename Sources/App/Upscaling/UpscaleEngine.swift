import UIKit
import CoreGraphics

/// 简单异步信号量：超分推理很吃内存和 ANE，串行执行。
/// 之前书架一次几十张封面同时推理，失败后移植代码会把输入缓冲当输出装配 → 整张黑图。
actor UpscaleGate {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { available = max(1, limit) }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// 图片超分入口：判断「值不值得放大」并跑 CoreML 模型。
/// 模型固定输出 2 倍分辨率，所以只有当原图比显示目标还小的时候才放大——
/// 原图本来就够大时再放大只是浪费内存和时间。
@MainActor
final class UpscaleEngine {
    static let shared = UpscaleEngine()
    private static let coverGate = UpscaleGate(limit: 1)
    private static let mangaGate = UpscaleGate(limit: 1)
    private init() {}

    /// 注入到 Engine 的执行器（App 启动时调用一次）。
    /// 封面的放大结果在这里做内存 + 磁盘缓存，调用方不用关心。
    static func register() {
        UpscaleRuntime.mangaUpscaler = { image, targetWidth in
            await UpscaleEngine.shared.upscaleManga(image, targetWidth: targetWidth)
        }
        UpscaleRuntime.coverUpscaler = { image, targetWidth, cacheKey in
            if let cached = UpscaleImageCache.image(forKey: cacheKey) {
                return cached.cgImage
            }
            guard let output = await UpscaleEngine.shared.upscaleCover(image, targetWidth: targetWidth) else {
                return nil
            }
            let stored = UIImage(cgImage: output)
            UpscaleImageCache.store(stored, forKey: cacheKey)
            return stored.cgImage
        }
    }

    /// 漫画页：`targetWidth` 是显示宽度（像素）。长条漫/超大图会被策略直接跳过。
    func upscaleManga(_ image: CGImage?, targetWidth: Int) async -> CGImage? {
        guard UpscaleSettings.mangaEnabled else { return nil }
        return await run(image, targetWidth: targetWidth, kind: .manga, gate: Self.mangaGate)
    }

    /// 封面：`targetWidth` 是封面位图目标宽度（像素）。
    func upscaleCover(_ image: CGImage?, targetWidth: Int) async -> CGImage? {
        guard UpscaleSettings.coverEnabled else { return nil }
        return await run(image, targetWidth: targetWidth, kind: .cover, gate: Self.coverGate)
    }

    /// 设置页「试跑一次」：用一张 64×64 小图跑通整条链路，返回结果描述。
    func selfTest() async -> String {
        let quality = UpscaleSettings.quality
        guard let image = Self.makeTestImage() else { return "测试图创建失败" }
        do {
            guard let model = try await UpscaleModelStore.shared.model(for: quality) else {
                return "没有可用模型，先在下面下载"
            }
            let start = Date()
            let output = await model.process(image)
            let cost = String(format: "%.2f", Date().timeIntervalSince(start))
            guard let output else { return "推理失败（\(cost)s），模型可能不兼容本机" }
            guard output.width == 128, output.height == 128 else {
                return "输出尺寸异常 \(output.width)×\(output.height)"
            }
            return "成功 2 倍（128×128），耗时 \(cost)s"
        } catch {
            return "模型加载失败：\(error.localizedDescription)"
        }
    }

    private static func makeTestImage() -> CGImage? {
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let offset = (y * side + x) * 4
                pixels[offset] = UInt8(x * 4)
                pixels[offset + 1] = UInt8(y * 4)
                pixels[offset + 2] = 180
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: CGColorRenderingIntent.defaultIntent)
    }

    private func run(_ image: CGImage?, targetWidth: Int, kind: UpscaleKind, gate: UpscaleGate) async -> CGImage? {
        guard let image else { return nil }
        let quality = UpscaleSettings.quality
        guard UpscaleSettings.shouldUpscale(pixelWidth: image.width,
                                            pixelHeight: image.height,
                                            targetWidth: targetWidth,
                                            quality: quality) else {
            UpscaleStats.shared.record(kind,
                "跳过：\(image.width)×\(image.height) 不小于显示宽度 \(targetWidth)px（或超出档位上限）")
            return nil
        }
        // 串行：并发推理容易在内存吃紧时失败，而失败一次就是一张黑图。
        await gate.acquire()
        defer { Task { await gate.release() } }
        do {
            guard let model = try await UpscaleModelStore.shared.model(for: quality) else {
                UpscaleStats.shared.record(kind, "跳过：还没下载模型（档位：\(quality.title)）")
                return nil // 没装模型就保持原图
            }
            let start = Date()
            let output = await model.process(image)
            let cost = String(format: "%.2fs", Date().timeIntervalSince(start))
            guard let output else {
                UpscaleStats.shared.record(kind, "失败：推理未成功（\(cost)），保持原图")
                UpscaleLog.error("推理失败，回退原图 \(image.width)x\(image.height)")
                return nil
            }
            UpscaleStats.shared.recordSuccess(kind, detail:
                "\(cost) · \(image.width)×\(image.height) → \(output.width)×\(output.height)")
            return output
        } catch {
            UpscaleStats.shared.record(kind, "失败：模型加载出错（\(error.localizedDescription)）")
            UpscaleLog.error("模型加载失败 \(error.localizedDescription)")
            return nil
        }
    }

    /// 效果对比用：无视尺寸策略直接跑一次（仍需要已装模型）。
    func upscaleForPreview(_ image: CGImage) async -> CGImage? {
        await Self.coverGate.acquire()
        defer { Task { await Self.coverGate.release() } }
        do {
            guard let model = try await UpscaleModelStore.shared.model(for: UpscaleSettings.quality) else {
                return nil
            }
            return await model.process(image)
        } catch {
            UpscaleLog.error("模型加载失败 \(error.localizedDescription)")
            return nil
        }
    }
}
