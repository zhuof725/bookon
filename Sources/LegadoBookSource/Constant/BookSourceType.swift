//
//  BookSourceType.swift
//  LegadoBookSource
//
//  对应 Kotlin: constant/BookSourceType.kt
//

import Foundation

public enum BookSourceType {
    public static let `default` = 0   // 0 文本
    public static let audio = 1       // 1 音频
    public static let image = 2       // 2 图片
    public static let file = 3        // 3 只提供下载服务的网站
    public static let video = 4       // 4 视频
}
