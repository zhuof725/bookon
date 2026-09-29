//
//  ReviewRule.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/ReviewRule.kt
//

import Foundation

/// 段评规则
public struct ReviewRule: Codable, Equatable {
    /// 段评URL
    @LenientOptionalString public var reviewUrl: String?
    /// 段评发布者头像
    @LenientOptionalString public var avatarRule: String?
    /// 段评内容
    @LenientOptionalString public var contentRule: String?
    /// 段评发布时间
    @LenientOptionalString public var postTimeRule: String?
    /// 获取段评回复URL
    @LenientOptionalString public var reviewQuoteUrl: String?

    // 这些功能将在以上功能完成以后实现
    /// 点赞URL
    @LenientOptionalString public var voteUpUrl: String?
    /// 点踩URL
    @LenientOptionalString public var voteDownUrl: String?
    /// 发送回复URL
    @LenientOptionalString public var postReviewUrl: String?
    /// 发送回复段评URL
    @LenientOptionalString public var postQuoteUrl: String?
    /// 删除段评URL
    @LenientOptionalString public var deleteUrl: String?

    // Kotlin 全字段默认 null。
    public init(
        reviewUrl: String? = nil,
        avatarRule: String? = nil,
        contentRule: String? = nil,
        postTimeRule: String? = nil,
        reviewQuoteUrl: String? = nil,
        voteUpUrl: String? = nil,
        voteDownUrl: String? = nil,
        postReviewUrl: String? = nil,
        postQuoteUrl: String? = nil,
        deleteUrl: String? = nil
    ) {
        self._reviewUrl = LenientOptionalString(wrappedValue: reviewUrl)
        self._avatarRule = LenientOptionalString(wrappedValue: avatarRule)
        self._contentRule = LenientOptionalString(wrappedValue: contentRule)
        self._postTimeRule = LenientOptionalString(wrappedValue: postTimeRule)
        self._reviewQuoteUrl = LenientOptionalString(wrappedValue: reviewQuoteUrl)
        self._voteUpUrl = LenientOptionalString(wrappedValue: voteUpUrl)
        self._voteDownUrl = LenientOptionalString(wrappedValue: voteDownUrl)
        self._postReviewUrl = LenientOptionalString(wrappedValue: postReviewUrl)
        self._postQuoteUrl = LenientOptionalString(wrappedValue: postQuoteUrl)
        self._deleteUrl = LenientOptionalString(wrappedValue: deleteUrl)
    }

    public enum CodingKeys: String, CodingKey {
        case reviewUrl
        case avatarRule
        case contentRule
        case postTimeRule
        case reviewQuoteUrl
        case voteUpUrl
        case voteDownUrl
        case postReviewUrl
        case postQuoteUrl
        case deleteUrl
    }
}
