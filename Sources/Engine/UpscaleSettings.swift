import Foundation
import CoreGraphics

/// 图片超分执行器：CoreML 实现在 App 层，Engine 只留注入点，
/// 这样封面加载这类「会被测试工程单独编译」的文件不用拖着整个超分模块。
/// 不注入（或注入后返回 nil）就保持原图。
enum UpscaleRuntime {
    /// 漫画页：(源图, 显示宽度像素) -> 放大后的图。
    static var mangaUpscaler: ((_ image: CGImage, _ targetWidth: Int) async -> CGImage?)?
    /// 封面：(源图, 显示宽度像素, 缓存键) -> 放大后的图（实现内部自己缓存）。
    static var coverUpscaler: ((_ image: CGImage, _ targetWidth: Int, _ cacheKey: String) async -> CGImage?)?
}

/// 图片超分档位。档位决定用哪个模型：快速走 waifu2x（1MB 级），高质量走 Real-ESRGAN（30MB 级）。
enum UpscaleQuality: String, CaseIterable, Identifiable {
    case fast
    case best

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "快速"
        case .best: return "高质量"
        }
    }

    var detail: String {
        switch self {
        case .fast: return "waifu2x：2 倍放大 + 去噪，1.1MB，每张约 0.1~0.3 秒"
        case .best: return "Real-ESRGAN：2 倍放大，34MB，每张约 0.3~1 秒"
        }
    }

    /// 模型仓库里的文件名（与 models.json 的 file 字段一致）。
    var modelFile: String {
        switch self {
        case .fast: return "waifu2x_photo_noise0_scale2x.mlmodel"
        case .best: return "RealESRGAN_x2plus.mlpackage"
        }
    }

    /// 单张输入的最大像素数：Real-ESRGAN 慢得多、也吃内存，上限压更低。
    /// 快速（waifu2x）约 800×2200，高质量（Real-ESRGAN）约 800×1500。
    var maxInputPixels: Int {
        switch self {
        case .fast: return 1_800_000
        case .best: return 1_200_000
        }
    }

    /// 对应模型的大致体积（用于设置页显示）。
    var modelSize: Int {
        switch self {
        case .fast: return 1_106_111
        case .best: return 34_115_143
        }
    }
}

/// 图片超分设置与「要不要放大」的策略。纯 Foundation，可离线回归。
/// 模型与推理在 App 层（Sources/App/Upscaling），这里只管开关、档位与尺寸策略。
enum UpscaleSettings {
    static let mangaKey = "reader.upscale.manga.v1"
    static let coverKey = "reader.upscale.cover.v1"
    static let qualityKey = "reader.upscale.quality.v1"

    /// 输入上限：超大图与长条漫不放大（内存与推理时间都会爆），保持原样显示。
    /// 放大是 2 倍输出，一张 800×1200 的页放大后解码约 15MB，更大的图要跳过。
    static let maxInputWidth = 1300
    static let maxInputHeight = 2200

    // MARK: 开关（UserDefaults，键名稳定）

    static var mangaEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: mangaKey) }
        set { UserDefaults.standard.set(newValue, forKey: mangaKey) }
    }

    static var coverEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: coverKey) }
        set { UserDefaults.standard.set(newValue, forKey: coverKey) }
    }

    static var quality: UpscaleQuality {
        get { UpscaleQuality(rawValue: UserDefaults.standard.string(forKey: qualityKey) ?? "") ?? .fast }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: qualityKey) }
    }

    // MARK: 策略

    /// 是否值得放大：原图比显示目标还小才有收益（超分补的是分辨率缺口）。
    /// 输入太大（长条漫、高清单图）直接跳过，避免内存和推理时间爆炸。
    static func shouldUpscale(pixelWidth: Int, pixelHeight: Int, targetWidth: Int,
                              quality: UpscaleQuality = .fast) -> Bool {
        guard pixelWidth > 0, pixelHeight > 0, targetWidth > 0 else { return false }
        guard pixelWidth <= maxInputWidth, pixelHeight <= maxInputHeight else { return false }
        guard pixelWidth * pixelHeight <= quality.maxInputPixels else { return false }
        return pixelWidth < targetWidth
    }

    /// 放大后图片的像素尺寸（模型输出固定 2 倍）。
    static func outputSize(pixelWidth: Int, pixelHeight: Int) -> (width: Int, height: Int) {
        (pixelWidth * 2, pixelHeight * 2)
    }
}
