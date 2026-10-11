# Floating reading menu

Reference: user screenshot `photo_B17AC9D6.png`, 2026-10-12.

- Top controls are independent surfaces: round back button, title/source capsule, round real book cover (placeholder if unavailable). Cover opens read-only book information.
- Bottom controls are a rounded, translucent panel: current chapter + position, previous/next **chapter** and within-chapter scrubber, then TOC / speech / chapter search / typography settings.
- Use actual book/source/chapter/progress data. Screenshot fixture text belongs only to tests.
- `ReaderChrome.swift` uses native material with theme tint, fine border and soft shadow; no opaque full-width toolbar and no full-screen dimmer. Reduced transparency uses a solid theme surface.
- `ReaderView` uses overlays, not safe-area insets: opening or dismissing the menu does not repaginate, change body margins, alter line breaks, or shift body baselines. Reading status bar remains hidden as previously requested. Underlying page-turn and paragraph comment paths remain unchanged.
- Scrubbing previews the target page and commits at gesture end. Paged mode displays current/total pages; continuous mode displays within-chapter percentage rather than fabricated page counts. Neighbor buttons are disabled at book boundaries and while loading.
- Speech uses the iOS speech synthesizer for the remainder of the loaded chapter from the current page; scroll mode starts at the current chapter's beginning. Tap again to stop. Changing chapters or exiting the reader stops speech. This is not an audiobook/background or automatic cross-chapter player.
- Search is explicitly **current chapter only**, without network requests: matching paragraphs and highlights, plus exact page jump using existing Character offsets in paged mode. Scroll mode shows the full matching paragraph without an inaccurate approximate jump. No automatic global search or book fetching.
- iOS 16+ deployment remains supported. Night theme, narrow width and large accessibility sizes are covered by the focused native UI fixture. Simulator tests cannot certify real-device glass appearance or audible speech quality.
