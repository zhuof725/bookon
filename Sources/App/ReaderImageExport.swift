import UIKit
import Photos

/// 正文图片的取图与导出。图片块可能是 data: URI（含 base64 / 百分号编码）或网络地址，
/// 这里与 ContentImageView 使用同一套解码规则，保证长按菜单和屏幕上看到的图一致。
enum ReaderImageExport {
    static func image(from src: String) async -> UIImage? {
        if src.hasPrefix("data:") {
            return decodeDataURI(src)
        }
        guard let url = URL(string: src), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return LocalCoverLocationImage(src)
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    /// data:image/... 的位图数据；解码规则在 Engine/DataURIDecode，便于离线回归。
    static func decodeDataURIData(_ src: String) -> Data? { DataURIDecode.data(src) }

    static func decodeDataURI(_ src: String) -> UIImage? {
        decodeDataURIData(src).flatMap(UIImage.init(data:))
    }

    private static func LocalCoverLocationImage(_ src: String) -> UIImage? {
        guard let url = URL(string: src), url.isFileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// 保存到相机胶卷。首次使用会请求「仅添加」权限，不读取相册内容。
    static func saveToPhotos(_ image: UIImage) async -> String {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        var granted = status == .authorized || status == .limited
        if status == .notDetermined {
            granted = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { result in
                    continuation.resume(returning: result == .authorized || result == .limited)
                }
            }
        }
        guard granted else { return "没有相册权限，请在系统设置中允许" }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                continuation.resume(returning: success ? "已保存到相机胶卷" : "保存失败")
            }
        }
    }
}
