import SwiftUI
import UIKit

/// 崩溃日志页：列出本机记录的闪退报告，可查看、复制、分享或清空。
struct CrashLogView: View {
    @ThemePalette private var palette
    @State private var reports: [CrashReporter.Report] = []
    @State private var selected: CrashReporter.Report?
    @State private var shareItem: ShareFile?
    @State private var notice: String?

    private struct ShareFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if reports.isEmpty {
                    Text("暂无崩溃日志。\n闪退后重新打开 App，记录会出现在这里。")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    ForEach(reports) { report in
                        Button { selected = report } label: { row(report) }
                            .buttonStyle(.plain)
                    }
                    HStack(spacing: 10) {
                        Button("复制全部") { copyAll() }
                            .buttonStyle(.bordered)
                        Button("分享全部") { shareAll() }
                            .buttonStyle(.bordered)
                        Spacer(minLength: 0)
                        Button("清空", role: .destructive) { clearAll() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
                Text("日志只保存在本机。发送给开发者可帮助定位闪退原因。")
                    .appFont(.caption)
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 2)
            }
            .padding(20)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle("崩溃日志")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .sheet(item: $selected) { report in detail(report) }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url]).ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if let notice {
                Text(notice)
                    .appFont(.caption)
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(palette.accent))
                    .padding(.bottom, 28)
                    .transition(.opacity)
            }
        }
    }

    private var surface: Color { palette.surface.opacity(palette.surfaceOpacity) }

    private func row(_ report: CrashReporter.Report) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.accent)
                Text(report.title)
                    .appFont(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            if !report.preview.isEmpty {
                Text(report.preview)
                    .appFont(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.border.opacity(0.6), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("crash.row.\(report.url.lastPathComponent)")
    }

    private func detail(_ report: CrashReporter.Report) -> some View {
        NavigationStack {
            ScrollView {
                Text(report.contents)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background { AppThemeCanvas().ignoresSafeArea() }
            .foregroundStyle(palette.primary)
            .navigationTitle(report.kind)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { selected = nil }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = report.contents
                        showNotice("已复制")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("复制")
                    Button {
                        shareItem = ShareFile(url: report.url)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享")
                }
            }
        }
    }

    private func reload() {
        reports = CrashReporter.reports()
    }

    private func copyAll() {
        UIPasteboard.general.string = CrashReporter.combinedText()
        showNotice("已复制全部日志")
    }

    private func shareAll() {
        let text = CrashReporter.combinedText()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legado-crash-logs.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        shareItem = ShareFile(url: url)
    }

    private func clearAll() {
        CrashReporter.deleteAll()
        reload()
        showNotice("已清空")
    }

    private func showNotice(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { if notice == text { notice = nil } }
        }
    }
}
