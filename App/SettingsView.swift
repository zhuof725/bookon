//
//  SettingsView.swift
//  书源调试
//
//  第 7 步 C 段返工：设置页。
//   - 超时 / 日志（原有）；
//   - 新增「文本上限」：两个独立 Stepper（源码显示上限、导出附带上限）+ 当前值说明 + 恢复默认；
//   - 「清除 Cookie」与「清除缓存」**分开**，且清的是 App 共享的持久化实例，不是新建的内存实例；
//   - 显示 App 版本 / commit hash / CI run 编号（读 Info.plist 的 BuildCommit / BuildCIRun）。
//
//  业务逻辑（钳位 / 持久化 / 恢复默认 / 清除）全在 BookonDebugKit，本文件只装配。
//

import SwiftUI
import BookonDebugKit
import LegadoBookSource

struct SettingsView: View {
    @Bindable var settings: DebugSettings
    let environment: SharedEnvironment

    @State private var message: String?
    @State private var buildInfo = AppBuildInfo.fromMainBundle()

    var body: some View {
        NavigationStack {
            Form {
                Section("超时（秒）") {
                    Stepper("连接超时：\(settings.connectTimeout)", value: $settings.connectTimeout, in: 1...120)
                    Stepper("读取超时：\(settings.readTimeout)", value: $settings.readTimeout, in: 1...300)
                    Stepper("总超时：\(settings.totalTimeout)", value: $settings.totalTimeout, in: 1...300)
                }

                Section("日志") {
                    Toggle("记录响应体", isOn: $settings.recordResponseBody)
                    Picker("详细级别", selection: $settings.verbosity) {
                        Text("普通").tag(DebugVerbosity.normal)
                        Text("仅错误").tag(DebugVerbosity.errorsOnly)
                    }
                }

                Section {
                    Stepper(value: $settings.sourceDisplayLimit,
                            in: DebugTextLimit.displayRange,
                            step: 5000) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("源码显示上限：\(settings.sourceDisplayLimit) 字符")
                            Text("源码页签最多显示这么多字符（按 Character 截断，不会切断 emoji）。")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $settings.exportSourceLimit,
                            in: DebugTextLimit.exportRange,
                            step: 1000) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("导出附带上限：\(settings.exportSourceLimit) 字符")
                            Text(settings.exportSourceLimit == 0
                                 ? "0 = 导出时不附带任何源码。"
                                 : "导出日志时每个阶段最多附带这么多字符。")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Button("恢复默认（\(DebugTextLimit.displayDefault) / \(DebugTextLimit.exportDefault)）") {
                        settings.restoreDefaultTextLimits()
                        message = "已恢复默认文本上限"
                    }
                } header: {
                    Text("文本上限")
                } footer: {
                    Text("显示范围 \(DebugTextLimit.displayRange.lowerBound)…\(DebugTextLimit.displayRange.upperBound)，"
                         + "导出范围 \(DebugTextLimit.exportRange.lowerBound)…\(DebugTextLimit.exportRange.upperBound)。")
                }

                Section("数据") {
                    Button("清除 Cookie") {
                        environment.clearCookies()
                        message = "已清除 Cookie"
                    }
                    Button("清除缓存", role: .destructive) {
                        environment.clearCache()
                        message = "已清除缓存"
                    }
                    if let message {
                        Text(message).foregroundStyle(.secondary)
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: buildInfo.version)
                    LabeledContent("Commit", value: buildInfo.commit)
                    LabeledContent("CI Run", value: buildInfo.ciRun)
                }
            }
            .navigationTitle("设置")
            .onAppear { buildInfo = AppBuildInfo.fromMainBundle() }
            .onChange(of: settings.connectTimeout) { _, _ in settings.save() }
            .onChange(of: settings.readTimeout) { _, _ in settings.save() }
            .onChange(of: settings.totalTimeout) { _, _ in settings.save() }
            .onChange(of: settings.recordResponseBody) { _, _ in settings.save() }
            .onChange(of: settings.verbosity) { _, _ in settings.save() }
            .onChange(of: settings.sourceDisplayLimit) { _, _ in settings.save() }
            .onChange(of: settings.exportSourceLimit) { _, _ in settings.save() }
        }
    }
}
