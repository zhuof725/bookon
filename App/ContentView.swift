//
//  ContentView.swift
//  书源调试
//
//  第 7 步 C 段返工：主界面（书源 / 调试 / 日志历史 / 设置 四个标签页）。
//  只做界面装配，业务逻辑全部委托 BookonDebugKit。
//
//  说明：调试页不再在页内选择书源——由「书源」标签列表点行进入（NavigationStack
//  navigationDestination），因此这里只需把共享环境与日志存储透传下去。
//

import SwiftUI
import BookonDebugKit
import LegadoBookSource

struct ContentView: View {
    @Bindable var repository: BookSourceRepository
    @Bindable var settings: DebugSettings
    let environment: SharedEnvironment
    let logStore: DebugLogStore

    var body: some View {
        TabView {
            SourceListView(
                repository: repository,
                settings: settings,
                environment: environment,
                logStore: logStore
            )
            .tabItem { Label("书源", systemImage: "books.vertical") }

            DebugView(
                repository: repository,
                settings: settings,
                environment: environment,
                logStore: logStore,
                source: nil
            )
            .tabItem { Label("调试", systemImage: "terminal") }

            LogHistoryView(logStore: logStore)
                .tabItem { Label("日志历史", systemImage: "doc.text") }

            SettingsView(settings: settings, environment: environment)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
