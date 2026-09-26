import SwiftUI

@main
struct BookOnApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            BookshelfView()
                .tabItem { Label("书架", systemImage: "books.vertical") }
            NavigationView { SearchView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            NavigationView { SourceListView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("书源", systemImage: "globe") }
            AboutView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}
