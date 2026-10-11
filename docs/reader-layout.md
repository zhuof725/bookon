# Reader layout decisions

## Current layout contract

- `ReaderTextLayout` owns native glyph shaping, fixed font metrics, Android line-height conversion and comment-tail wrapping.
- `ReaderPaginator` selects measured TextKit line boundaries; source blocks, character offsets and same-length quote display mappings remain separate.
- The Android reading units are preserved: line height and paragraph spacing are stored as tenths of the actual font height, then converted to points at the UIKit boundary. The default is `12` for line height (`1.2H`) and `2` for paragraph spacing (`0.2H`).
- Body paragraphs use two measured full-width indent cells on their first line. `textFullJustify` and `textBottomJustify` are independent switches. The final row of a real paragraph remains natural; a page fragment that continues on the next page can justify its visible final row.
- Page bottom alignment follows legado-E `TextPage.upLinesPosition()`: only a near-full pure-text page receives the remaining height distributed across row gaps; a short terminal page keeps natural top spacing. The footer and chapter title remain outside the body layout.
- The paginator uses complete TextKit rows, carries comment attachments only on the final fragment, and does not add general widow/orphan control because the Android reference does not implement it in this path.

## Android source consulted

The uploaded reference is `legado-E-main`. The layout rules come from:

- `app/src/main/java/io/legado/app/ui/book/read/page/provider/TextChapterLayout.kt`
- `app/src/main/java/io/legado/app/ui/book/read/page/provider/ZhLayout.kt`
- `app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt`
- `app/src/main/java/io/legado/app/ui/book/read/page/entities/TextPage.kt`
- `app/src/main/java/io/legado/app/help/book/ContentProcessor.kt`

The iOS implementation ports the default text height/spacing, measured indent, full justification switch, complete-row pagination and near-full-page vertical distribution through TextKit. `useZhLayout` remains an optional Android mode and is not enabled by the iOS default.

## Verification

The reader interaction harness should cover complete-row pagination, source/UTF-16 reconstruction, comment-tail attachment placement, measured line height, paragraph gaps, full justification and near-full-page bottom distribution. CI remains the authoritative Swift/Xcode build check because this Linux workspace does not include Xcode.
