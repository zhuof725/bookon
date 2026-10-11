# Reader layout decisions

## Current layout contract

- `ReaderTextLayout` owns native glyph shaping, fixed font metrics, Android line-height conversion and comment-tail wrapping.
- `ReaderPaginator` selects measured TextKit line boundaries; source blocks, character offsets and same-length quote display mappings remain separate.
- The Android reading units are preserved: line height and paragraph spacing are stored as tenths of the actual font height, then converted to points at the UIKit boundary. The default is `12` for line height (`1.2H`) and `2` for paragraph spacing (`0.2H`).
- Body paragraphs use two measured full-width indent cells on their first line. `textFullJustify` and `textBottomJustify` are independent switches. The final row of a real paragraph remains natural; a page fragment that continues on the next page can justify its visible final row.
- Latest correction: **bottom alignment must never sacrifice top alignment**. Every text page starts at its body top margin (after the title on chapter page one). With bottom alignment ON, near-full pure-text pages distribute their spare space across row gaps, keeping both the first and last baselines fixed. To avoid visibly stretched pages, the spare must be less than one natural line advance and each added gap no more than 10% of that advance. Sparse terminal/single-row pages remain top-aligned with natural spacing and blank space BELOW; they are never translated down or stretched over the whole page. Bottom alignment OFF leaves natural spacing on all pages. Titles, footers, source text, page cuts and bubble geometry are unchanged.
- `BookPage.alignsBodyBottom` now records that a page actually fills its region through bounded row-gap distribution. It is never a view-alignment instruction. `PageContentView` always uses `.topLeading`, fixes each paragraph to its measured line-box height, and sums each gap once. Tests check first AND last baselines against independently computed targets on every page, including short pages with bottom alignment ON.
- The paginator uses complete TextKit rows, carries comment attachments only on the final fragment, and does not add general widow/orphan control because the Android reference does not implement it in this path.

## Android source consulted

The uploaded reference is `legado-E-main`. The layout rules come from:

- `app/src/main/java/io/legado/app/ui/book/read/page/provider/TextChapterLayout.kt`
- `app/src/main/java/io/legado/app/ui/book/read/page/provider/ZhLayout.kt`
- `app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt`
- `app/src/main/java/io/legado/app/ui/book/read/page/entities/TextPage.kt`
- `app/src/main/java/io/legado/app/help/book/ContentProcessor.kt`

The iOS implementation ports the default text height/spacing, measured indent, full justification switch, complete-row pagination and near-full-page vertical distribution through TextKit. `useZhLayout` remains an optional Android mode and is not enabled by the iOS default.

## Screenshot bubble reference

`photo_590CCBC1.png` (1206×2622) is the user's visual target, not a claim of a whole-chapter device reproduction. At 23pt/@3x, bubbles 1/3/23/4 share a 103×79px ink outline, inside a 109×85px canvas. The canvas starts at the preceding punctuation's full glyph advance (not its ink edge). The outline starts 3px later; its top is baseline−70px and its bottom is baseline+9px. These measurements scale with body font size. The font baseline was inferred by matching PingFang SC glyph metrics, not read from image metadata.

`CommentBubble` uses two continuous closed Bezier contours traced from the supplied outline, with a transparent hollow body/tail junction. The counter is rendered separately with native CoreText; both one/two-digit counts keep the same outline width and ink-centered digits. The historical quarter-em separator now has zero advance, preserving UTF-16 mapping while removing the extra offset. Attachment bounds are the single geometry source for layout and drawing; hit testing reads actual attachment glyph geometry. Font line metrics reserve these bubble extents even without a comment so adding a bubble cannot move the final baseline.

The outline oracle and original counter crop are test-only PNG fixtures, not bundled screenshots or content in the production application. Anti-aliasing and number-font rasterization can differ by OS; pixel tolerances and measured relative coordinates must be reported separately from an unverified claim of pixel identity.

## Verification

The reader interaction harness should cover complete-row pagination, source/UTF-16 reconstruction, comment-tail attachment placement, measured line height, paragraph gaps, full justification and near-full-page bottom distribution. CI remains the authoritative Swift/Xcode build check because this Linux workspace does not include Xcode.
