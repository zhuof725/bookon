# TXT table-of-contents rules

Entry: My / Library Management / Directory Rules (我的 → 书库管理 → 目录规则).

The 15 read-only bundled categories follow the supplied screenshots: 第 X 章/节/回, 第 X 话/幕, 卷+章组合, 序章/楔子/尾声, Chapter N, CHAPTER N, Roman headings, numeric punctuation headings, Chinese-number punctuation headings, bracketed chapter, bracketed title, volume, number+space+title, equals separators, dash separators. Patterns are displayed verbatim on cards. Unicode Chinese zero forms/two, fullwidth delimiters and optional spaces are supported. The volume preset accepts both 第X卷 and 卷X.

The attached `legado-E-main.zip` was inspected at `app/src/main/assets/defaultData/txtTocRule.json`, `app/src/main/assets/web/help/md/txtTocRuleHelp.md`, and the local TextFile parser. Its default list has different names and more entries than the screenshots. This is an independent iOS implementation of the screenshot's 15 categories, not an import of all Android presets or Android-only JavaScript rule processing.

- Builtins are always present, read-only, and testable with a sample title.
- Custom rules support creation, sample matching, editing, deletion with confirmation and local persistence. Invalid expressions, empty-match expressions, blank names and oversized inputs are rejected. Limit 50 customs, 512 regex characters, 60-character names.
- Import snapshots and compiles rules once. New TXT imports match each complete candidate line against builtin + custom patterns; overlapping matches split only once. Candidate lines are limited to 160 UTF-16 units. Cooperative regex progress cancellation limits pathological backtracking; it is not a complete regex sandbox.
- No headings => existing size-based fallback. One heading => retain the actual title rather than replacing it with 第1部分. A real 前言 heading is preserved, while small pre-title metadata follows the prior importer convention.
- No automatic rebuild of existing book caches/progress. Reimport is required to parse an old TXT with new rules; the existing reimport behavior is unchanged. EPUB spine/TOC and website ruleToc are untouched.
- Rule page/editor use the shared monochrome AppPalette. No blue theme or copied screenshot content is inserted.

Validation: focused standalone macOS Foundation/Compression regression + native rule UI fixture + production iOS build. Offline fixtures do not claim live source/network or full user-device import validation.
