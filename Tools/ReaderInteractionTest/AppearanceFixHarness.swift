import SwiftUI
import UIKit

struct AppearanceFixHarness: View {
    @StateObject private var store: AppThemeStore
    @State private var ready = false
    @State private var report = "pending"
    @State private var assetID: String?
    init() {
        let defaults = UserDefaults(suiteName: "io.legado.appearance.fix.fixture")!
        defaults.removePersistentDomain(forName: "io.legado.appearance.fix.fixture")
        _store = StateObject(wrappedValue: AppThemeStore(defaults: defaults))
    }
    var body: some View {
        NavigationStack {
            if ready { AppAppearanceSettingsView(store: store) }
            else { ProgressView() }
        }
        .preferredColorScheme(.light)
        .overlay(alignment: .bottom) {
            Text(report).font(.system(size: 1)).foregroundStyle(.clear)
                .accessibilityIdentifier("fix.report").allowsHitTesting(false)
        }
        .task {
            guard !ready else { return }
            do {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let wallpaper = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 200), format: format).pngData { c in
                    UIColor(red: 0.15, green: 0.45, blue: 0.9, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 120, height: 200))
                }
                let id = try ThemeAssetStore.shared.importData(wallpaper); assetID = id
                var theme = AppTheme.custom(); theme.name = "背景回归"; theme.customization?.pageBackgroundImage = id
                try store.save(theme, apply: true)
                report = try iconChecks() ? "PASS" : "FAIL"
                ready = true
            } catch { report = "FAIL \(error)"; ready = true }
        }
        .onDisappear { if let assetID { ThemeAssetStore.shared.remove(assetID) } }
    }
    private func iconChecks() throws -> Bool {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let assets = ThemeAssetStore(directory: dir)
        func data(transparent: Bool, blank: Bool = false) -> Data {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = !transparent
            return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: f).pngData { c in
                if !transparent { UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 32, height: 32)) }
                if !blank { UIColor.black.setFill(); c.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
                    UIColor.white.setFill(); c.fill(CGRect(x: 13, y: 13, width: 6, height: 6)) }
            }
        }
        func alpha(_ image: UIImage, _ x: Int, _ y: Int) -> Int {
            var b = [UInt8](repeating: 0, count: 32 * 32 * 4)
            b.withUnsafeMutableBytes { raw in
                let ctx = CGContext(data: raw.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            return Int(b[(y * 32 + x) * 4 + 3])
        }
        for transparent in [true, false] {
            let input = data(transparent: transparent)
            let source = dir.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".png")
            try input.write(to: source); defer { try? FileManager.default.removeItem(at: source) }
            let id = try assets.importIconFile(source)
            guard id.hasSuffix(".png"), ThemeAssetStore.isValidID(id),
                  let image = ThemeAssetStore(directory: dir).image(for: id),
                  alpha(image, 0, 0) == 0, alpha(image, 10, 10) == 255,
                  alpha(image, 15, 15) == 255, try Data(contentsOf: source) == input else { return false }
            assets.remove(id); guard assets.image(for: id) == nil else { return false }
        }
        let blank = try assets.importIconData(data(transparent: false, blank: true))
        guard let image = assets.image(for: blank), alpha(image, 0, 0) == 255 else { return false }
        let old = try assets.importData(data(transparent: false))
        return old.hasSuffix(".jpg") && assets.image(for: old) != nil && !ThemeAssetStore.isValidID("../fake.png")
    }
}
