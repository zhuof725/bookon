# Editable app themes

The application appearance preference (`app.appearance.v1`: system/light/dark) remains separate from the chosen color theme. Existing installations keep their preference and default to Classic Monochrome.

## User flow

我的 → 书库管理 → 外观主题 opens a wallpaper-inspired theme gallery: browse large rounded previews, then explicitly apply a theme. The + action opens a template gallery; a template becomes a user-owned draft in the full-screen editor. Built-in themes can be customized by creating a copy, not overwritten.

Custom themes have a name, solid/gradient background style, and separate light/dark background, gradient-end, card-surface and accent colors. Text and primary-button labels resolve automatically for contrast. Editing is local to the draft: switching preview light/dark or canceling does not change the application theme or system appearance preference. Saving creates/updates a theme; applying a new theme is a separate action. Saving edits to the active theme refreshes application-owned views in place.

Themes can be edited again or deleted after confirmation. Removing the active custom theme falls back to Classic Monochrome. Native colors are edited with public SwiftUI ColorPicker; built-in templates and quick swatches give a simpler starting point. The interface takes inspiration from iOS wallpaper selection but does not modify iOS wallpapers or use Apple wallpaper assets. Photo wallpaper import is not included in this version.

## Storage and boundaries

`AppThemeStore` stores a versioned Codable snapshot under `app.customThemes.v1`, with at most 20 user themes and 40 characters per name. Each custom theme has a stable UUID. Opaque six-digit sRGB colors are validated. Background/card colors must remain readable in their light/dark variant, and accent colors need readable contrast for links and controls. Invalid or unreadable stored data falls back safely without changing the bookshelf or reader data.

`ThemePalette` is a DynamicProperty reading the selected AppTheme and colorScheme from SwiftUI Environment. AppThemeRoot observes the repository; no root `.id`, UIKit swizzle, global mutable palette or app restart is used. Existing MonochromeAppStyle now inherits the environment tint instead of resetting nested pages to monochrome. The original static AppPalette stays as the neutral default/reference for existing tests.

The theme applies to app-owned shelf/detail/search/settings surfaces, cards, buttons and labels. Real cover images, external websites and native system-owned pickers are not recolored. The reader's saved paper/background, typography, layout, pagination, content and reading progress are unchanged. Destructive/error warnings keep their native semantics.

## Verification

The custom-themes simulator suite uses isolated preferences and the actual store/gallery/editor plus production shelf/detail components. It covers theme persistence, create/edit/cancel/apply/delete, limits/invalid data, and propagation without rebuilding root state. Screenshot attachments document the native gallery/editor. Fixtures are not a claim of full on-device or all-Dynamic-Type/system-picker coverage. Release builds verify the complete application compiles.
