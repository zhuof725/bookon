import SwiftUI
import UIKit

/// NavigationStack stays outside this root so pushed screens replace the bar.
/// On iOS 26 the system owns the Liquid Glass appearance, sizing and labels.
/// `accessory` 挂在底栏上方（iOS 26 是系统自带的 tabViewBottomAccessory，
/// 老系统叠在自定义底栏上），用来放迷你播放条之类的常驻控件。
struct LibraryTabContainer<Shelf: View, Discover: View, Explore: View, Profile: View, SearchTab: View, Accessory: View>: View {
    @Binding var selection: LibraryTab
    @Environment(\.appTheme) private var theme
    @State private var icons: [String: UIImage] = [:]
    let shelf: Shelf
    let discover: Discover
    let explore: Explore
    let profile: Profile
    let search: SearchTab
    let accessoryVisible: Bool
    let accessory: Accessory

    init(selection: Binding<LibraryTab>, accessoryVisible: Bool = false,
         @ViewBuilder shelf: () -> Shelf,
         @ViewBuilder discover: () -> Discover,
         @ViewBuilder explore: () -> Explore, @ViewBuilder profile: () -> Profile,
         @ViewBuilder search: () -> SearchTab,
         @ViewBuilder accessory: () -> Accessory) {
        _selection = selection
        self.shelf = shelf(); self.discover = discover()
        self.explore = explore()
        self.profile = profile(); self.search = search()
        self.accessoryVisible = accessoryVisible
        self.accessory = accessory()
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // 迷你播放条挂在每个 Tab 内容的底部安全区上：没在播时什么都不占，
                // 也不会像系统 tabViewBottomAccessory 那样「空着也画一条玻璃条」，
                // 更不会因为运行时增删配件让整个 TabView 重建（书架顶部会多出一截空白）。
                TabView(selection: $selection) {
                    tab(shelf, .shelf)
                    tab(discover, .discover)
                    tab(explore, .explore)
                    tab(profile, .profile)
                    tab(search, .search)
                }
            } else {
                Group {
                    switch selection {
                    case .shelf: shelf
                    case .discover: discover
                    case .explore: explore
                    case .statistics: explore
                    case .profile: profile
                    case .search: search
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if accessoryVisible { accessory }
                        LibraryDock(selection: $selection)
                    }
                }
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

    @ViewBuilder private func tab<V: View>(_ content: V, _ value: LibraryTab) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if accessoryVisible { accessory }
            }
            .tabItem { item(value) }
            .tag(value)
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

/// 没有底部配件的老调用方（UI 测试夹具也走这个初始化器）。
extension LibraryTabContainer where Accessory == EmptyView {
    init(selection: Binding<LibraryTab>, @ViewBuilder shelf: () -> Shelf,
         @ViewBuilder discover: () -> Discover,
         @ViewBuilder explore: () -> Explore, @ViewBuilder profile: () -> Profile,
         @ViewBuilder search: () -> SearchTab) {
        self.init(selection: selection, accessoryVisible: false, shelf: shelf, discover: discover,
                  explore: explore, profile: profile, search: search, accessory: { EmptyView() })
    }
}
