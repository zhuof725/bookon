import UIKit
import CoreGraphics

/// 图片超分入口：判断「值不值得放大」并跑 CoreML 模型。
/// 模型固定输出 2 倍分辨率，所以只有当原图比显示目标还小的时候才放大——
/// 原图本来就够大时再放大只是浪费内存和时间。
@MainActor
final class UpscaleEngine {
    static let shared = UpscaleEngine()
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
        return await run(image, targetWidth: targetWidth)
    }

    /// 封面：`targetWidth` 是封面位图目标宽度（像素）。
    func upscaleCover(_ image: CGImage?, targetWidth: Int) async -> CGImage? {
        guard UpscaleSettings.coverEnabled else { return nil }
        return await run(image, targetWidth: targetWidth)
    }

    /// 是否已装好当前档位要用的模型（设置页显示状态用）。
    func hasModelForCurrentQuality() async -> Bool {
        let quality = UpscaleSettings.quality
        if await UpscaleModelStore.shared.isInstalled(quality.modelFile) { return true }
        let installed = await UpscaleModelStore.shared.installedFileNames()
        return !installed.isEmpty
    }

    private func run(_ image: CGImage?, targetWidth: Int) async -> CGImage? {
        guard let image else { return nil }
        guard UpscaleSettings.shouldUpscale(pixelWidth: image.width,
                                            pixelHeight: image.height,
                                            targetWidth: targetWidth) else {
            return nil
        }
        do {
            guard let model = try await UpscaleModelStore.shared.model(for: UpscaleSettings.quality) else {
                return nil // 没装模型就保持原图
            }
            let output = await model.process(image)
            if output == nil {
                UpscaleLog.error("推理失败，回退原图 \(image.width)x\(image.height)")
            }
            return output
        } catch {
            UpscaleLog.error("模型加载失败 \(error.localizedDescription)")
            return nil
        }
    }
}
