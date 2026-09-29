#!/usr/bin/env python3
# 校验：Kotlin 各实体的持久化字段是否都在 Swift 里实现。
# 手工从 Kotlin 源码提取字段清单（仅数据字段，排除 @Ignore / 方法 / companion）。
import re, sys

KOTLIN = {
 "BookSource": ["bookSourceUrl","bookSourceName","bookSourceGroup","bookSourceType","bookUrlPattern","customOrder","enabled","enabledExplore","jsLib","enabledCookieJar","concurrentRate","header","loginUrl","loginUi","loginCheckJs","coverDecodeJs","bookSourceComment","variableComment","lastUpdateTime","respondTime","weight","exploreUrl","exploreScreen","ruleExplore","searchUrl","ruleSearch","ruleBookInfo","ruleToc","ruleContent","ruleReview","eventListener","customButton"],
 "SearchRule": ["checkKeyWord","bookList","name","author","intro","kind","lastChapter","updateTime","bookUrl","coverUrl","wordCount"],
 "ExploreRule": ["bookList","name","author","intro","kind","lastChapter","updateTime","bookUrl","coverUrl","wordCount"],
 "BookInfoRule": ["init","name","author","intro","kind","lastChapter","updateTime","coverUrl","tocUrl","wordCount","canReName","downloadUrls"],
 "TocRule": ["preUpdateJs","chapterList","chapterName","chapterUrl","formatJs","isVolume","isVip","isPay","updateTime","nextTocUrl"],
 "ContentRule": ["content","subContent","title","nextContentUrl","webJs","sourceRegex","replaceRegex","imageStyle","imageDecode","payAction","callBackJs"],
 "ReviewRule": ["reviewUrl","avatarRule","contentRule","postTimeRule","reviewQuoteUrl","voteUpUrl","voteDownUrl","postReviewUrl","postQuoteUrl","deleteUrl"],
 "BookListRule": ["bookList","name","author","intro","kind","lastChapter","updateTime","bookUrl","coverUrl","wordCount"],
 "ExploreKind": ["title","url","type","action","chars","default","viewName","style"],
 "FlexChildStyle": ["layout_flexGrow","layout_flexShrink","layout_alignSelf","layout_flexBasisPercent","layout_wrapBefore","layout_justifySelf"],
 "RowUi": ["name","type","action","chars","default","viewName","style"],
 "Book": ["bookUrl","tocUrl","origin","originName","name","author","kind","customTag","coverUrl","customCoverUrl","intro","customIntro","charset","type","group","latestChapterTitle","latestChapterTime","lastCheckTime","lastCheckCount","totalChapterNum","durChapterTitle","durChapterIndex","durVolumeIndex","chapterInVolumeIndex","durChapterPos","durChapterTime","wordCount","canUpdate","order","originOrder","variable","readConfig","syncTime"],
 "Book.ReadConfig": ["reverseToc","pageAnim","reSegment","imageStyle","useReplaceRule","delTag","ttsEngine","splitLongChapter","readSimulating","startDate","startChapter","dailyChapters","openCredits","closeCredits","playMode","playSpeed"],
 "BookChapter": ["url","title","isVolume","baseUrl","bookUrl","index","isVip","isPay","resourceUrl","tag","wordCount","start","end","startFragmentId","endFragmentId","variable","imgUrl"],
 "SearchBook": ["bookUrl","origin","originName","type","name","author","kind","coverUrl","intro","wordCount","latestChapterTitle","tocUrl","time","variable","originOrder","chapterWordCountText","chapterWordCount","respondTime"],
 "BaseBook": ["name","author","bookUrl","kind","wordCount","variable","infoHtml","tocHtml"],
 "BaseSource": ["concurrentRate","loginUrl","loginUi","header","enabledCookieJar","jsLib"],
}

# Swift 文件到类型的映射
FILES = {
 "BookSource": "Sources/LegadoBookSource/BookSource.swift",
 "SearchRule": "Sources/LegadoBookSource/Rule/SearchRule.swift",
 "ExploreRule": "Sources/LegadoBookSource/Rule/ExploreRule.swift",
 "BookInfoRule": "Sources/LegadoBookSource/Rule/BookInfoRule.swift",
 "TocRule": "Sources/LegadoBookSource/Rule/TocRule.swift",
 "ContentRule": "Sources/LegadoBookSource/Rule/ContentRule.swift",
 "ReviewRule": "Sources/LegadoBookSource/Rule/ReviewRule.swift",
 "BookListRule": "Sources/LegadoBookSource/Rule/BookListRule.swift",
 "ExploreKind": "Sources/LegadoBookSource/Rule/ExploreKind.swift",
 "FlexChildStyle": "Sources/LegadoBookSource/Rule/FlexChildStyle.swift",
 "RowUi": "Sources/LegadoBookSource/Rule/RowUi.swift",
 "Book": "Sources/LegadoBookSource/Book.swift",
 "Book.ReadConfig": "Sources/LegadoBookSource/Book.swift",
 "BookChapter": "Sources/LegadoBookSource/BookChapter.swift",
 "SearchBook": "Sources/LegadoBookSource/SearchBook.swift",
 "BaseBook": "Sources/LegadoBookSource/BaseBook.swift",
 "BaseSource": "Sources/LegadoBookSource/BaseSource.swift",
}

import os
base = "/var/minis/workspace/bookon"
missing = {}
for typ, fields in KOTLIN.items():
    path = os.path.join(base, FILES[typ])
    text = open(path).read()
    miss = []
    for f in fields:
        # 检查 CodingKeys / var 声明 / case 是否出现该字段名
        # init 是关键字，Swift 里写作 `init` 或 CodingKeys case `init`
        name = f
        # 用词边界匹配字段名（含反引号形式）
        pat = re.compile(r'\b`?'+re.escape(name)+r'`?\b')
        if not pat.search(text):
            miss.append(f)
    if miss:
        missing[typ] = miss

print("=== 字段覆盖校验 ===")
total_k = sum(len(v) for v in KOTLIN.values())
print(f"Kotlin 数据字段总数: {total_k}")
if not missing:
    print("结果: Kotlin 有但 Swift 没实现的字段清单 —— 空。全部覆盖。")
else:
    print("结果: 存在未覆盖字段：")
    for t, m in missing.items():
        print(f"  {t}: {m}")
    sys.exit(1)
