//
//  BookonDebugApp.swift
//  书源调试
//
//  第 7 步 C 段：SwiftUI App 入口（iOS 17+）。
//  全部业务逻辑在 BookonDebugKit；本文件只做界面装配，不写业务。
//

import SwiftUI
import BookonDebugKit
import LegadoBookSource

@main
struct BookonDebugApp: App {
    @State private var repository = BookSourceRepository()
    @State private var settings = DebugSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(repository: repository, settings: settings)
        }
    }
}
