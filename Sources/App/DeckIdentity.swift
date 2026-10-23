import Foundation

/// 一个板块的身份：书源 + 分类。
///
/// 卡片类模板需要它来记住「滑到第几张」——同一本书源下不同分类是不同的板块，
/// 位置必须分开记，否则切换板块会串位。
struct DeckIdentity: Hashable {
    var sourceUrl: String
    var kindUrl: String

    /// 拼出「模板 + 书源 + 分类」的位置键，同一个板块换了模板要各记各的。
    func key(for template: DiscoverTemplateKind) -> String {
        DeckPositionStore.key(template: template, sourceUrl: sourceUrl, kindUrl: kindUrl)
    }
}
