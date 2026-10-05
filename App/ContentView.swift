//
//  ContentView.swift
//  书源调试
//
//  第 7 步 C 段：主界面（书源 / 调试 / 设置 三个标签页）。
//  只做界面装配，业务逻辑全部委托 BookonDebugKit。
//

import SwiftUI
import BookonDebugKit
import LegadoBookSource

struct ContentView: View {
    @Bindable var repository: BookSourceRepository
    @Bindable var settings: DebugSettings

    var body: some View {
        TabView {
            SourceListView(repository: repository)
                .tabItem { Label("书源", systemImage: "books.vertical") }

            DebugView(repository: repository, settings: settings)
                .tabItem { Label("调试", systemImage: "terminal") }

            SettingsView(settings: settings)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
