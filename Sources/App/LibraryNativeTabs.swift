import SwiftUI
import UIKit

/// NavigationStack stays outside this root so pushed screens replace the bar.
/// On iOS 26 the system owns the Liquid Glass appearance, sizing and labels.
struct LibraryTabContainer<Shelf: View, Discover: View, Statistics: View, Profile: View, SearchTab: View, Home: View>: View {
    @Binding var selection: LibraryTab
    @Environment(\.appTheme) private var theme
    @State private var icons: [String: UIImage] = [:]
    let shelf: Shelf
    let discover: Discover
    let statistics: Statistics
    let profile: Profile
    let search: SearchTab
    let home: Home

    init(selection: Binding<LibraryTab>, @ViewBuilder shelf: () -> Shelf,
         @ViewBuilder discover: () -> Discover,
         @ViewBuilder statistics: () -> Statistics, @ViewBuilder profile: () -> Profile,
         @ViewBuilder search: () -> SearchTab,
         @ViewBuilder home: () -> Home) {
        _selection = selection
        self.shelf = shelf(); self.discover = discover()
        self.statistics = statistics()
        self.profile = profile(); self.search = search()
        self.home = home()
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                TabView(selection: $selection) {
                    home.tabItem { item(.home) }.tag(LibraryTab.home)
                    shelf.tabItem { item(.shelf) }.tag(LibraryTab.shelf)
                    discover.tabItem { item(.discover) }.tag(LibraryTab.discover)
                    profile.tabItem { item(.profile) }.tag(LibraryTab.profile)
                    search.tabItem { item(.search) }.tag(LibraryTab.search)
                }
                // 下滑时底栏收成一个：iOS 26 的 TabView 原生支持，交给系统做，
                // 自己写一套只会和系统玻璃背景打架。
                .tabBarMinimizeBehavior(.onScrollDown)
                // No custom material/background/UITabBarAppearance: retain native glass.
            } else {
                Group {
                    switch selection {
                    case .home: home
                    case .shelf: shelf
                    case .discover: discover
                    case .statistics: statistics   // 已并入「我的」，仅保留入口不影响已存选择
                    case .profile: profile
                    case .search: search
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { LibraryDock(selection: $selection) }
            }
        }
        .task(id: theme.customization?.tabIcons) {
            let overrides = theme.customization?.tabIcons ?? [:]
            let loaded = await Task.detached(priority: .utility) {
                var result: [String: UIImage] = [:]
                for (key, value) in overrides where ThemeAssetStore.isValidID(value) {
                    guard let image = ThemeAssetStore.shared.image(for: value) else { continue }
                    let size = CGSize(width: 25, height: 25)
                    let scale = min(size.width / image.size.width, size.height / image.size.height)
                    let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    result[key] = UIGraphicsImageRenderer(size: size).image { _ in
                        image.draw(in: CGRect(x: (25 - fitted.width) / 2, y: (25 - fitted.height) / 2,
                                              width: fitted.width, height: fitted.height))
                    }.withRenderingMode(.alwaysOriginal)
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            icons = loaded
        }
    }

    @ViewBuilder private func item(_ tab: LibraryTab) -> some View {
        let value = theme.customization?.tabIcons?[tab.key]
        if let value, ThemeAssetStore.isValidID(value), let image = icons[tab.key] {
            Image(uiImage: image)
        } else if let value, ThemeAssetStore.shared.symbolImage(for: value) != nil {
            Image(systemName: value)
        } else {
            Image(systemName: tab.symbol)
        }
        Text(tab.title)
    }
}
