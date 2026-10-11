# Reader layout decisions

## Current layout contract

- ReaderTextLayout owns native glyph shaping, fixed line metrics and comment-tail wrapping.
- ReaderPaginator selects measured TextKit line boundaries; source blocks, character offsets and same-length quote display mappings remain separate.
- PageContentView renders those blocks without changing tracking, line spacing or paragraph spacing to consume spare page height. The footer remains separate.
- A new multi-line paragraph must not start with only one line at the end of a nonempty page when the next page can hold at least two of its lines. Move its start forward at a real line boundary instead. Complete one-line paragraphs and extremely short page areas are exempt.
- On every text page, including a short terminal page, the body block is anchored to the same bottom edge above the footer. The chapter title remains at the top. This deliberately leaves unused space above a short body, rather than stretching its internal gaps. Volume title pages keep their existing separate layout.
- This step does not implement general widow control or automatic per-page paragraph-gap distribution. Mixed image/card pages bottom-align their content block; the text baseline guarantee applies when the final content is a text line.

## Reference consulted

Yuedu-reader, revision `b24d525b966d3ea3a7d650c884cd12e4c19153c0`:

`Modules/Core/ReaderCore/CoreText/CoreTextPaginator.swift`

The source defines an `applyOrphanControl` helper describing paragraph-start orphan and paragraph-end widow handling. Its page-range generator separately obtains the visible range from CoreText and protects page boundaries. The presence of that helper is not evidence that its caller is enabled in that revision; the local inspected tree contains only the definition.

This project uses an independently implemented TextKit capacity check during pagination, not that CoreText range-rewriting routine. No upstream implementation or dependency was copied. The reference project's license must be reviewed separately before any future code reuse.

## Verification

ReaderPageFlowAudit includes the reported chapter-23 text, plus three exact-capacity cases at 19/26/32 pt where the old fit-only rule could take one row of a new paragraph. Tests require the preceding page to retain only its completed paragraph, the next page to begin the new paragraph with at least two rows, exact source reconstruction and offsets, no height overflow, and the comment attachment only on the final fragment.
