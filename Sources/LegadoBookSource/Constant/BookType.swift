//
//  BookType.swift
//  LegadoBookSource
//
//  对应 Kotlin: constant/BookType.kt
//
//  以二进制位来区分,可能一本书籍包含多个类型,每一位代表一个类型,数值为2的n次方
//  以二进制位来区分,数据库查询更高效, 数值>=8和老版本类型区分开
//  仅移植数据模型需要用到的常量（Book.type / origin 默认值等）。
//

import Foundation

enum BookType {
    /// 4 视频
    static let video = 0b100
    /// 8 文本
    static let text = 0b1000
    /// 16 更新失败
    static let updateError = 0b10000
    /// 32 音频
    static let audio = 0b100000
    /// 64 图片
    static let image = 0b1000000
    /// 128 只提供下载服务的网站
    static let webFile = 0b10000000
    /// 256 本地
    static let local = 0b100000000
    /// 512 压缩包 表明书籍文件是从压缩包内解压来的
    static let archive = 0b1000000000
    /// 1024 未正式加入到书架的临时阅读书籍
    static let notShelf = 0b100_0000_0000

    /// 本地书源标记
    static let localTag = "loc_book"
}
