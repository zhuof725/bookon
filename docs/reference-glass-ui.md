# Reference glass list UI (photo_6FC61463)

UI only: preserve existing labels, destinations, callbacks, storage, book covers and reading layout. Do not add the reference app's history/favorites/subscription/sponsorship/about entries. Do not bundle the screenshot or invent a wallpaper.

The existing profile and statistics list rows now use independent continuous rounded glass surfaces (24pt), 56pt minimum row height, 20pt internal horizontal padding, 24pt page padding, 8pt inter-row spacing, rose line icons and subdued chevrons. Native glass and Reduce Transparency continue through AppGlassModifier. No accent/theme preference is overwritten; the rose color is local to these navigation icons. Existing grouping headings remain. Dynamic Type can increase height rather than truncate content.

The eight existing customization navigation rows share the rose icon/glass silhouette and remove separator lines; their Form navigation behavior and draft transactions are unchanged. Bookshelf, detail and reader layouts are not restructured by this list-only visual reference.

SettingsGlassTests uses the actual production row components with isolated callbacks, checks labels/spacing/width, narrow 320pt dark accessibility text, and rejects reference-only feature labels. NativeTabsGlassTests continues to check actual blur and chroma rather than a flat translucent fill. The gradient in the harness is test-only, not a new production wallpaper. Main app Release compilation covers full profile/statistics destinations; the fixture does not exercise AppStore/network or every navigation target.
