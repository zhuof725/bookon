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
            AboutView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}
