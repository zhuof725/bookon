import SwiftUI

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: "book.fill")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text("BookOn").font(.title2).bold()
                            Text("开源阅读 iOS 版").foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section(header: Text("信息")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(version).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("参考项目")
                        Spacer()
                        Text("Legado").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("我的")
        }
        .navigationViewStyle(.stack)
    }
}
