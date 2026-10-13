# Theme appearance redesign — model and real component integration

## Model/API contract

All six additions belong to `AppThemeSwatches`, independently in `AppTheme.light` and `.dark`:

```swift
var primaryText: String? = nil
var secondaryText: String? = nil
var border: String? = nil
var selection: String? = nil
var cardRadius: Double? = nil
var cardBorder: Bool? = nil
```

The existing four-color memberwise initializer remains valid. No custom Codable implementation or storage migration is introduced. Synthesized optional decoding accepts missing/null fields; encoding omits nil values. `app.customThemes.v1`, snapshot version 1, UUID identity, draft semantics, save/apply/delete behavior and store limits are unchanged. All original preset values are unchanged. Existing snapshots therefore retain their computed color defaults rather than receiving baked-in replacements.

`ResolvedAppPalette` retains every original property. Added API:

- `cardRadius: CGFloat`: current light/dark swatch value, default 20, defensively clamped to 8...30; non-finite draft values fall back to 20.
- `cardBorder: Bool`: current swatch value, default true.
- `cornerRadius(default:)`: explicit radius when present; otherwise the caller's legacy radius.
- `usesOpaqueSurfaces: Bool`: explicit primary/secondary/selection colors use a known surface behind shared glass controls, instead of validating against an unpredictable material.

`AppTheme.cardRadiusRange` and `.defaultCardRadius` are shared constants, not stored theme-wide settings. `AppThemeSwatches.readableBackgrounds(style:)` and `.resolvedInk(style:)` share the backgrounds and resolved text/selection calculations between validation and rendering. Geometry-only edits of Classic Monochrome do not change its native dynamic colors.

## Validation

`AppTheme.validationMessage` validates both appearance variants before the unchanged store can save:

1. Existing name constraints and strict opaque six-digit sRGB hex validation. Every non-nil added color joins `allColors`; empty strings, alpha colors and invalid hex are rejected.
2. Each explicit radius must be finite and in 8...30. Palette clamping is only defensive draft rendering, not permission to save an invalid radius.
3. Preserve the fixed native light/dark text checks (101010/F5F5F5) and accent contrast at least 4.5:1 against the surface and page background. Gradients retain the original 13-point sampling, including both endpoints. Custom text cannot bypass the native navigation/title readability rule.
4. Explicit primary and secondary text each require at least 4.5:1 against those page/surface backgrounds.
5. If primary, secondary or selection is explicit, resolved primary, secondary and accent each require at least 4.5:1 against the actual resolved selection color. Explicit unreadable selection is rejected, not silently replaced. Automatic selected tint falls back to surface if required; automatic secondary can fall back to primary. All-nil legacy themes retain the original calculation and acceptance rules.

Borders are decorative and only hex-validated; no claim is made that every selected border has 3:1 non-text contrast. Gradient checking remains sampled rather than a continuous mathematical proof. `onAccent` still resolves automatically to black/white; it is not replaced by custom primary text.

## Controls that actually propagate

| Control | Real consumers and limits |
| --- | --- |
| Background, gradient end, solid/gradient | Existing `AppThemeCanvas` app screens; no wallpaper import or reader-paper binding. |
| Surface | Existing palette-backed cards/lists, including book detail and the new library grouped cards. Shelf glass retains its legacy material when added text/selection controls are nil; explicit text/selection uses opaque surface for predictable contrast. |
| Accent | Existing app tint, actions, links, metadata pills and library icons; destructive/error semantics are untouched. |
| Primary text | Existing `palette.primary` consumers: shelf titles, detail content, app labels, library titles/values, navigation rows and recent books. Native system navigation titles/pickers are not recolored. |
| Secondary text | Existing `palette.secondary` consumers, plus explicit library section headings, value labels and chevrons. Native `LabeledContent` value styling is avoided in those app-owned rows. |
| Border | Existing palette outlines and library separators. Card-outline visibility is controlled separately; control/dock/menu outlines and separators do not disappear when card borders are disabled. |
| Selection | Existing detail metadata capsules, cache status capsule, TOC-rule badges, library dock selected capsule and other existing palette-selected controls. No new selection behavior or fake menu/reader binding is introduced. |
| Card radius | Detail summary/introduction/TOC cards, library statistics/profile groups, bookshelf grid title cards and list cards. The TOC hit shape matches the visible detail radius. |
| Card border | Those same card surfaces only. Not cover borders, dock geometry, navigation circles, menu shapes or reader layout. |

Nil radius preserves detail 25pt, shelf title 13pt and shelf list 18pt via `cornerRadius(default:)`. Newly app-owned library groups use the resolved 20pt default. Card borders default to true: the detail/library surfaces get a subtle 0.5pt outline; existing shelf card outlines keep their 0.5pt width. The default appearance is intentionally approximate, not pixel-identical.

Library statistics/profile now use ScrollView + app-owned grouped cards rather than attempting to override native grouped-list clipping. Navigation destinations, identifiers, ordering and statistics calculations are retained. Explicit 44pt-minimum row content and large-text wrapping are preserved. Helpers are private to `LibraryNavigation.swift`; no new cross-file helper dependency is required by the interaction harness.

## Theme hub and editor

The hub follows the compact reference layout: a four-column grid of small color cards at the top, names below each, and New as the next tile in the same grid. The current theme has a strong outline/checkmark; a browsed, unapplied theme gets a subtle dashed outline. Accessibility text sizes use two columns. Thumbnails reflect the current light/dark scheme and saved theme tokens; all saved themes remain reachable, with no eight-item cap or preset display aliases. Search and all/built-in/custom filtering are tucked behind the toolbar search button. App appearance switching and plain theme editing/action rows follow below on a white/dark canvas, without the previous large selected-theme summary card. Browsing and applying remain separate; only Use changes the selected theme. Template selection creates a draft, save reveals its action rows, and delete confirmation/fallback remain. The template picker and editor retain their existing previews. This layout change adds no reader binding, fake navigation rows or new stored preferences.

The editor has a fixed light/dark selector, a compact live component preview and four bottom sections: Colors, Background, Cards, Controls. It supports native color pickers, quick accent colors and an exact hex sheet. The hex sheet accepts six-digit RGB or opaque FFRRGGBB (optional leading #), normalizes to RGB, rejects translucent/invalid values, and applies only on confirmation. Cancel keeps the draft unchanged. App-owned UI typography still follows the selected font.

Colors and card settings are independent per light/dark variant. Solid/gradient style remains shared by both variants, as in the existing data model. Saving an active theme updates its appearance; saving a new draft does not apply it until the explicit use action. Switching preview mode never changes the app appearance preference. Theme management chrome remains neutral so invalid draft colors cannot obscure its controls.

Not added: wallpaper files, native menu blur overrides, resource binding, reader-paper binding, theme import/export, or placeholder entrances for unsupported screenshot features. No renderer, pagination, ReadSettings, book data, remote requests or real cover image changes are involved.

## Verification scope

The macOS custom-themes suite includes production-store model checks, legacy four-field JSON, extended fields and palette resolution, invalid-save guards, create/apply/edit/cancel/delete, search/filter/browse-only behavior, exact hex editing, light/dark persistence, 320pt shelf/detail previews, and existing Appearance/Theme/Shelf/Detail regression tests. Tests use isolated preferences and synthetic book fixtures, not user library data. Release compilation additionally covers LibraryNavigation's app-owned grouped cards; that page is not in the focused UI harness.

CI outcomes and native screenshots must be reviewed before release. Static Linux checks do not establish Swift compilation, native rendering or VoiceOver behavior. Card borders have no enforced non-text contrast threshold and gradient contrast checking is sampled.
