# Book detail screenshot update

Reference: `photo_BAB718AA.png`. Book cover, title, author, words, category, reading state, tags, introduction, latest chapter and catalog size are populated from real `Book`, cached or fetched `BookChapter` data. Unknown word counts, update times and chapter counts are omitted, not copied from the screenshot. `kind` may provide tags; no recommendation metadata is invented.

Tap a bookshelf cover to open this detail. Top controls: back and More (refresh metadata, catalog). Main actions: start/continue reading, category selection, find identical name+author in other enabled sources, add/remove shelf with destructive confirmation. Source switching previews another book/source without deleting local files or automatically replacing the original shelf entry. Edited introductions and category labels are local per-book preferences, not changes to external websites. Catalog reads local/cached chapters first then requests missing data. Chapter selection starts at that chapter, overriding saved chapter/position only after content loads successfully. Existing reader layout/turning remains unchanged.

No fake book cover/title/836 chapter count/229.7万字/date is added to production. The focused simulator fixture uses synthetic content and no network, so full live-source/device behavior needs an on-device check.
