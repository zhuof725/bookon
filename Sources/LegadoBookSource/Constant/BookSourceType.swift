//
//  BookSourceType.swift
//  LegadoBookSource
//
//  对应 Kotlin: constant/BookSourceType.kt
//

import Foundation

enum BookSourceType {
    static let `default` = 0   // 0 文本
    static let audio = 1       // 1 音频
    static let image = 2       // 2 图片
    static let file = 3        // 3 只提供下载服务的网站
    static let video = 4       // 4 视频
}
