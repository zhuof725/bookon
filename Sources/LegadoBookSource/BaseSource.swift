//
//  BaseSource.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/BaseSource.kt
//
//  Kotlin 里 BaseSource 是一个 interface，除了声明下列可持久化字段外，
//  还包含大量 JS 执行 / 登录 / 请求头解析 / 缓存等运行时方法
//  （login()、getHeaderMap()、evalJS()、getLoginInfo() 等）。
//  本步骤只做数据模型，不做规则解析引擎 / 网络请求，
//  因此这里只移植 interface 声明的「数据字段」，运行时方法留待后续步骤。
//
//  TODO(后续步骤): 移植 BaseSource 的运行时行为
//    - getLoginJs() / login()
//    - getHeaderMap() / getLoginHeaderMap() / putLoginHeader() 等
//    - getLoginInfo() / getLoginInfoMap() / putLoginInfo()
//    - setVariable() / getVariable() / put() / get()
//    - evalJS() 及 JS 引擎绑定
//    这些属于「规则解析引擎 / 网络请求」范畴，按任务要求本步骤不实现。
//

import Foundation

/// 书源基类协议，声明可持久化的公共字段。
/// 对应 Kotlin `interface BaseSource : JsExtensions` 中的属性部分。
public protocol BaseSource {
    /// 并发率
    var concurrentRate: String? { get set }
    /// 登录地址
    var loginUrl: String? { get set }
    /// 登录UI
    var loginUi: String? { get set }
    /// 请求头
    var header: String? { get set }
    /// 启用cookieJar
    var enabledCookieJar: Bool? { get set }
    /// js库
    var jsLib: String? { get set }

    /// 对应 Kotlin getTag()
    func getTag() -> String
    /// 对应 Kotlin getKey()
    func getKey() -> String
}
