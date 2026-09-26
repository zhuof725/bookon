import SwiftUI

struct BookshelfView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Image(systemName: "book.closed")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("书架空空如也")
                    .font(.headline)
                Text("后续版本将支持导入本地 TXT 和书源")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("书架")
        }
        .navigationViewStyle(.stack)
    }
}
