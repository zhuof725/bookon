import SwiftUI
import UIKit

/// 效果对比：拿一本书的封面，把「原图像素」和「超分后同区域」放在一起看。
/// 左边按最近邻放大（能看到模糊/锯齿），右边是超分后的同一块（同样大小显示）。
struct UpscaleCompareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ThemePalette private var palette

    @State private var originalCrop: UIImage?
    @State private var upscaledCrop: UIImage?
    @State private var status = "准备中…"
    @State private var sizes = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    cropCard(title: "原图（放大看像素）", image: originalCrop, pixelated: true)
                    cropCard(title: "超分后同区域", image: upscaledCrop, pixelated: false)
                }
                if !sizes.isEmpty {
                    Text(sizes)
                        .appFont(.caption).foregroundStyle(palette.primary)
                        .accessibilityIdentifier("upscale.compare.sizes")
                }
                Text(status)
                    .appFont(.footnote).foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("upscale.compare.status")
                Spacer(minLength: 0)
            }
            .padding(20)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("封面超分对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task { await run() }
    }

    private func cropCard(title: String, image: UIImage?, pixelated: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.surface)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(pixelated ? .none : .high)
                        .scaledToFit()
                        .padding(2)
                } else {
                    ProgressView().tint(palette.accent)
                }
            }
            .frame(height: 200)
            Text(title)
                .appFont(.caption).foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func run() async {
        guard let book = AppStore.shared.books.first(where: { BookCoverLocation.url(for: $0) != nil }),
              let url = BookCoverLocation.url(for: book) else {
            status = "没有找到本地封面：先加一本带封面的书，再回来对比。"
            return
        }
        guard let original = await decode(url: url, maxPixel: 1200) else {
            status = "封面解码失败：\(book.name)"
            return
        }
        sizes = "《\(book.name)》原图 \(original.width)×\(original.height)"
        status = "正在推理…"
        guard let upscaled = await UpscaleEngine.shared.upscaleForPreview(original) else {
            status = "推理失败或没有可用模型。先在上面下载模型，或用「试跑一次」看具体原因。"
            return
        }
        sizes = "《\(book.name)》 \(original.width)×\(original.height) → \(upscaled.width)×\(upscaled.height)"
        status = "左边是把原图放大到同样大小（能看到糊/锯齿），右边是超分后的同一块区域。"
        let sourceWidth = CGFloat(original.width)
        let sourceHeight = CGFloat(original.height)
        let cropWidth = max((sourceWidth / 3).rounded(), 32)
        let cropHeight = max((sourceHeight / 3).rounded(), 32)
        let sourceRect = CGRect(x: ((sourceWidth - cropWidth) / 2).rounded(),
                                y: ((sourceHeight - cropHeight) / 2).rounded(),
                                width: cropWidth, height: cropHeight)
        originalCrop = original.cropping(to: sourceRect).map { UIImage(cgImage: $0) }
        let scaledRect = CGRect(x: sourceRect.origin.x * 2, y: sourceRect.origin.y * 2,
                                width: cropWidth * 2, height: cropHeight * 2)
        upscaledCrop = upscaled.cropping(to: scaledRect).map { UIImage(cgImage: $0) }
    }

    private func decode(url: URL, maxPixel: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL,
                                                          [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel
                  ] as CFDictionary) else { return nil }
            return image
        }.value
    }
}
