//
//  BookonDebugApp.swift
//  书源调试
//
//  第 7 步 C 段返工：SwiftUI App 入口（iOS 17+）。
//  全部业务逻辑在 BookonDebugKit；本文件只做界面装配，不写业务。
//
//  本次返工要点：
//   - 注入**全 App 唯一**的 SharedEnvironment（Cookie/缓存持久化到 Documents），
//     使 Cookie 与缓存跨次调试保留，且设置页的「清除」清的就是这份实例。
//   - 启动时把当前构建信息（版本/commit/CI run）写入日志导出头。
//

import SwiftUI
import BookonDebugKit
import LegadoBookSource

@main
struct BookonDebugApp: App {
    /// 全 App 共享的 Cookie / 缓存实例（持久化在 Documents 下）。
    @State private var environment = SharedEnvironment.makeDefault()
    @State private var repository = BookSourceRepository()
    @State private var settings = DebugSettings()
    @State private var logStore = DebugLogStore()

    var body: some Scene {
        WindowGroup {
            ContentView(
                repository: repository,
                settings: settings,
                environment: environment,
                logStore: logStore
            )
        }
    }
}
