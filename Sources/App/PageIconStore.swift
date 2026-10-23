import Foundation
import UIKit

/// 页面自定义图标（从相册选的图）的落盘存取。
///
/// 只把文件名写进 `customDiscover.json`，图片本体放
/// `Application Support/LegadoReading/page-icons/<文件名>.png`：
/// 页面配置会被频繁整体重写（切页、加板块），把几百 KB 的图片塞进那份 JSON
/// 会让每次保存都变慢，也会让配置不好读。
enum PageIconStore {
    static let directoryName = "page-icons"

    static var directory: URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        } catch {
            return nil
        }
    }

    static func fileURL(for name: String) -> URL? {
        guard !name.isEmpty else { return nil }
        return directory?.appendingPathComponent(name)
    }

    /// 把相册图片缩到 256px 的方形 PNG 存起来，返回文件名；失败返回 nil。
    /// 方形裁切、保留透明：图标在胶囊按钮里只占 15pt，原图尺寸没有意义。
    static func save(image: UIImage, pageID: String) -> String? {
        guard let directory else { return nil }
        let square = squareThumbnail(image, side: 256)
        guard let data = square.pngData() else { return nil }
        // 文件名带页面 id：同一页换图直接覆盖，不会堆垃圾文件
        let cleanID = pageID.replacingOccurrences(of: "/", with: "-")
        let name = "\(cleanID).png"
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func load(named name: String?) -> UIImage? {
        guard let name, !name.isEmpty, let url = fileURL(for: name),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func remove(named name: String?) {
        guard let name, !name.isEmpty, let url = fileURL(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 居中裁成正方形再缩放：非方形图直接拉伸会变形。
    static func squareThumbnail(_ image: UIImage, side: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let edge = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - edge) / 2, y: (size.height - edge) / 2)
        let target = CGRect(x: 0, y: 0, width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: -origin.x * (side / edge),
                                  y: -origin.y * (side / edge),
                                  width: size.width * (side / edge),
                                  height: size.height * (side / edge)))
        }
    }
}
