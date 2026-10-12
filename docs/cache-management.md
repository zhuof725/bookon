# Cache management

Entry: 我的 → 本机数据 → 缓存管理. The page uses the existing monochrome palette and the user's global font selection.

The page scans on entry and supports refresh, per-category clearing and clearing all listed categories. Each clear requires confirmation. It reports logical disk file bytes, file counts, the number of cached in-memory chapters and URLCache's reported disk/memory usage. These values are NOT total application storage or guaranteed physical storage recovered.

Managed categories:
- Online chapter contents: shared ChapterContentCache memory, in-flight loads, SHA256-named `Caches/chapters/content-v2/*.txt`, and legacy `Caches/chapters/c_<MD5>.txt`.
- Online catalogs: `Caches/chapters/toc_<MD5>.json` only.
- Network responses: `URLCache` memory/disk responses via the platform API. This may include remote image responses; it is not an independently enumerable image cache.

Only recognized ordinary files directly inside these directories are managed. Unknown files, nested directories and symlinks are not followed or recursively removed. Clearing is coordinated with the chapter-cache actor, including invalidating pre-clear flights so an old response cannot repopulate cleared memory/disk. A new read/network request may cache data again.

Protected data includes Documents/LocalBooks (TXT/EPUB chapters and cover.img), ReadingFonts and manifest, bookshelf/reading progress, sources, login cookies/credentials, preference and rule data, and search history. No entire Documents/Caches/tmp tree is deleted. WebKit site data/cookies and already rendered image/page state are not purged. The page explicitly explains that online chapters/catalogs may need network access after clearing.

A failed deletion is reported rather than silently described as success, and sizes are rescanned after operations. Verification uses isolated temporary storage and URLCache instances; real user cache or personal files are not deleted by the tests.
