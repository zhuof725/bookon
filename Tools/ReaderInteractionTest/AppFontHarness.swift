import SwiftUI
import UIKit

struct AppFontHarnessView: View {
    @State private var detail = false
    @State private var field = "Root field ABC 123"
    @State private var report = "pending"
    @State private var stage = 0
    @State private var large = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Switch font") { advance() }.accessibilityIdentifier("appfont.next")
                Button("Page") { detail.toggle() }.accessibilityIdentifier("appfont.page")
                Button("Size") { large.toggle() }.accessibilityIdentifier("appfont.size")
            }.font(.system(size: 12))
            TextField("Root field", text: $field).accessibilityIdentifier("appfont.field")
                .textFieldStyle(.roundedBorder).padding(.horizontal)
            Text("Inherited body ABC 123").accessibilityIdentifier("appfont.implicit")
            Group {
                if detail { DetailHarnessView() }
                else { ShelfHarnessView() }
            }
            Text(report).font(.system(size: 8)).lineLimit(1)
                .accessibilityLabel(report).accessibilityIdentifier("appfont.report")
        }
        .modifier(AppTypographyRoot())
        .dynamicTypeSize(large ? .accessibility2 : .large)
        .onAppear { verify() }
    }

    private func advance() {
        do {
            let manager = ReadingFontManager.shared
            if manager.importedFonts.isEmpty {
                _ = try manager.importFont(from: FontFixture.asset(FontFixture.sans + ".ttf"))
            }
            stage += 1
            try manager.select(stage % 2 == 1 ? FontFixture.sans : "")
            verify()
        } catch { report = "FAIL: \(error)" }
    }

    private func verify() {
        let name = ReadingFontManager.shared.selectedPostScriptName
        let styles: [AppFontStyle] = [.body, .headline, .caption, .title2.weight(.bold), .system(size: 13)]
        var ok = true
        for style in styles {
            let resolved = style.uiFont(name)
            if !name.isEmpty { ok = ok && resolved.fontName == name }
            else { ok = ok && style.resolve("") == style.original }
            ok = ok && style.uiFont(name, category: .accessibilityExtraExtraExtraLarge).pointSize > resolved.pointSize
        }
        ok = ok && AppFontStyle.body.resolve("missing-font-name") == AppFontStyle.body.original
        report = "\(ok ? "PASS" : "FAIL") stage=\(stage) face=\(name.isEmpty ? "system" : name) rootField=\(field)"
    }
}
