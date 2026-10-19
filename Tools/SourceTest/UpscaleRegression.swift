import Foundation

/// 图片超分的档位与尺寸策略（纯计算，不涉及 CoreML 推理）。
enum UpscaleRegression {
    static func run(_ check: (Bool, String) -> Void) {
        // 档位：rawValue 稳定（UserDefaults 存的是 rawValue）。
        check(UpscaleQuality.allCases == [.fast, .best], "超分：两个档位")
        check(UpscaleQuality.fast.rawValue == "fast" && UpscaleQuality.best.rawValue == "best",
              "超分：档位存储值稳定")
        check(UpscaleQuality(rawValue: "best") == .best && UpscaleQuality(rawValue: "x") == nil,
              "超分：档位可还原，未知值回退默认")
        check(UpscaleQuality.fast.modelFile.hasSuffix(".mlmodel")
              && UpscaleQuality.best.modelFile.hasSuffix(".mlpackage"),
              "超分：档位对应模型文件")
        check(UpscaleQuality.fast.modelSize > 0 && UpscaleQuality.best.modelSize > UpscaleQuality.fast.modelSize,
              "超分：模型体积（快速 1MB 级、高质量 30MB 级）")
        check(!UpscaleQuality.fast.detail.isEmpty && !UpscaleQuality.best.detail.isEmpty,
              "超分：档位说明文案")

        // 尺寸策略：只放大「比显示目标还小」的图，长条漫/超大图跳过。
        check(UpscaleSettings.shouldUpscale(pixelWidth: 800, pixelHeight: 1200, targetWidth: 1170),
              "超分：小于显示尺寸才放大")
        check(!UpscaleSettings.shouldUpscale(pixelWidth: 1400, pixelHeight: 2100, targetWidth: 1170),
              "超分：原图已够大不放大")
        check(!UpscaleSettings.shouldUpscale(pixelWidth: 600, pixelHeight: 900, targetWidth: 600),
              "超分：与显示尺寸相同不放大")
        check(UpscaleSettings.shouldUpscale(pixelWidth: 599, pixelHeight: 900, targetWidth: 600),
              "超分：比显示尺寸小一点也放大")
        check(!UpscaleSettings.shouldUpscale(pixelWidth: 800, pixelHeight: 6000, targetWidth: 1170),
              "超分：长条漫跳过（高度上限）")
        check(!UpscaleSettings.shouldUpscale(pixelWidth: 1600, pixelHeight: 2400, targetWidth: 2000),
              "超分：超宽图跳过（宽度上限）")
        check(!UpscaleSettings.shouldUpscale(pixelWidth: 1100, pixelHeight: 2000, targetWidth: 1400),
              "超分：像素总量超限跳过")
        check(UpscaleSettings.shouldUpscale(pixelWidth: 800, pixelHeight: 1200, targetWidth: 1170,
                                            quality: .best)
              && !UpscaleSettings.shouldUpscale(pixelWidth: 800, pixelHeight: 1600, targetWidth: 1170,
                                                quality: .best)
              && UpscaleSettings.shouldUpscale(pixelWidth: 800, pixelHeight: 1600, targetWidth: 1170,
                                               quality: .fast),
              "超分：高质量档（Real-ESRGAN）输入上限更严")
        check(UpscaleQuality.fast.maxInputPixels > UpscaleQuality.best.maxInputPixels,
              "超分：快速档允许更大的输入")
        check(!UpscaleSettings.shouldUpscale(pixelWidth: 0, pixelHeight: 100, targetWidth: 600)
              && !UpscaleSettings.shouldUpscale(pixelWidth: 100, pixelHeight: 100, targetWidth: 0),
              "超分：非法尺寸不放大")
        check(UpscaleSettings.outputSize(pixelWidth: 800, pixelHeight: 1200).width == 1600
              && UpscaleSettings.outputSize(pixelWidth: 800, pixelHeight: 1200).height == 2400,
              "超分：输出是 2 倍")
        check(UpscaleSettings.maxInputWidth * UpscaleSettings.maxInputHeight
              > UpscaleQuality.fast.maxInputPixels,
              "超分：像素上限是实际生效的约束（不是死代码）")
    }
}
