import SwiftUI
import UIKit

struct LiveAppearanceHarness: View {
    @State private var draft = AppTheme.custom()
    @State private var scheme: ColorScheme = .light
    @State private var page: ThemeEditorDestination = .shelf
    @State private var splash = false
    @State private var closed = 0
    @State private var selected = 0
    private let pages: [ThemeEditorDestination] = [.tab, .shelf, .cover, .launch, .colors, .background, .effect, .cards]
    var body: some View {
        NavigationStack {
            ThemeCustomizationEditor(draft: $draft, previewScheme: $scheme, destination: page,
                                     importImage: { _ in }, importIcon: { _ in })
                .environment(\.appTheme, draft)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Menu("预览页") {
                            ForEach(pages, id: \.rawValue) { item in
                                Button(item.title) { page = item }.accessibilityIdentifier("fixture.page." + item.rawValue)
                            }
                        }.accessibilityIdentifier("fixture.pages")
                        Button("改草稿") {
                            draft.customization?.coverWidth = 60
                            draft.customization?.shelfColumns = 2
                            draft.customization?.glowIntensity = 0.2
                            draft.customization?.surfaceOpacity = 0.4
                            draft.light.cardRadius = 30
                        }.accessibilityIdentifier("fixture.change")
                        Button("启动图") { splash = true }.accessibilityIdentifier("fixture.splash")
                        Text("\(closed)").accessibilityIdentifier("fixture.closed")
                    }.appFont(.caption).padding(8).background(.regularMaterial)
                }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $splash) {
            ThemeLaunchOverlay(image: UIImage(systemName: "book")!) { splash = false; closed += 1 }
        }
    }
}

struct IndependentRowsHarness: View {
    @State private var count = 0
    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<4) { index in
                    Button("设置项目 \(index)") { count += 1 }
                        .accessibilityIdentifier("independent.row.\(index)")
                        .independentGlassRow()
                }
            }
            .scrollContentBackground(.hidden)
            .background(LinearGradient(colors: [.blue.opacity(0.4), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom))
            .navigationTitle("独立玻璃行")
            .safeAreaInset(edge: .bottom) { Text("\(count)").accessibilityIdentifier("independent.count") }
        }
    }
}
