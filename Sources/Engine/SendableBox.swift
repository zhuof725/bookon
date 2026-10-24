import Foundation

/// 跨并发域传递「内部自带同步、但类型本身没声明 Sendable」的值（宿主闭包、缓存对象等）。
///
/// Swift 6 的 `sending` 检查只看类型声明，不看调用点语义。项目里有些闭包是
/// 「后台线程调用、内部再切回主线程」的（比如图片解码钩子、音色探测），
/// 用这个盒子把意图写清楚，而不是给整个类型套 @unchecked Sendable。
struct SendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
