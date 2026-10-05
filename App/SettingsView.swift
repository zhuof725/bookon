//
//  SettingsView.swift
//  书源调试
//
//  第 7 步 C 段：设置页（超时 / 记录响应体 / 详细级别 / 清 Cookie 缓存）。
//  业务逻辑委托 BookonDebugKit.DebugSettings / DebugEnvironment。
//

import SwiftUI
import BookonDebugKit
import LegadoBookSource

struct SettingsView: View {
    @Bindable var settings: DebugSettings
    @State private var clearedMessage: String?

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

                Section("数据") {
                    Button("清除 Cookie 与缓存") {
                        DebugEnvironment.clearAll(
                            cookieStore: CookieStore(),
                            cacheManager: CacheManager()
                        )
                        clearedMessage = "已清除"
                    }
                    if let clearedMessage {
                        Text(clearedMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .onChange(of: settings.connectTimeout) { _, _ in settings.save() }
            .onChange(of: settings.readTimeout) { _, _ in settings.save() }
            .onChange(of: settings.totalTimeout) { _, _ in settings.save() }
            .onChange(of: settings.recordResponseBody) { _, _ in settings.save() }
            .onChange(of: settings.verbosity) { _, _ in settings.save() }
        }
    }
}
