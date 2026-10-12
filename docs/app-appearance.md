# Monochrome app appearance

The user explicitly selected the ENTIRE APP for black/white/gray styling, not only the bookshelf.

- `AppPalette` owns neutral, dynamic light/dark tokens. `MonochromeAppStyle` on the production root passes a black/white accent to navigation, buttons, links, selection controls and presented SwiftUI sheets.
- Bookshelf menu glyphs and selection marks use neutral colors. Actual cover images remain full color; missing-cover fallback is a gray gradient.
- Book-detail status/category/kind/latest tags have gray capsules and neutral text; the catalog link no longer uses blue; background is neutral rather than cool blue-gray.
- Search, statistics, profile and source-management backgrounds follow the same surface family; existing list hierarchy and reading history logic remain unchanged.
- Chapter VIP markers, native verification navigation, search-result highlighting and reader comment category badges use neutral app colors. Pure UIKit native toolbars use dynamic label tint.
- Real book images, external login/verification/comment website content, emoji, and user-selected reader paper themes are not globally desaturated. Existing stored reader theme/font/pagination/progress are untouched.
- Native destructive-role red and existing explicit error red stay available for warning semantics. No delete/confirmation protections are changed.
- Source books still have no Edit Introduction entry; local books keep it.

Validation: main app compile plus the focused `appearance` simulator suite covering theme tokens/native controls, bookshelf, detail and reader menus. Offline component fixtures do not certify live-network or device-specific system-picker/web-content styling.
