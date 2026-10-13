# Bookshelf list reference photo_0D44DBED

Only list view changes. Keep grid layout, top toolbar, sorting/filtering, default grid preference, selection/removal, import/search and tap-to-details callbacks unchanged. Menu: More → View → List.

List: 10pt side margins/gaps, continuous 18pt glass card (honors theme radius/card settings), 16x14pt padding, left 70x102 cover with 7pt corners, right title + author/count + read chapter + source + latest chapter/date. Normal row minimum 130pt; large accessibility text wraps with a 58x84 cover and no badge, no forced fixed card height. Real cover pipeline is unchanged.

New ShelfListSummary is an in-memory presentation value, no Book schema/storage migration. Production lazily reads existing localToc/cachedToc for visible list rows via AppStore; never downloads chapters or changes reading position. Count excludes volume headers. Missing TOC means count/badge are omitted, not zero. Latest date only comes from the matching last cached chapter's updateTime, never addedAt/lastReadAt. Latest title prefers actual Book.lastChapter. Missing author/source/latest use honest placeholders. Numeric badge means remaining chapters AFTER current (excluding volume headers), not newly updated chapters. It only appears when current index exists in known TOC and reading has started, with 99+ cap. No fabricated genre badge or screenshot books.

Offline UI tests use production BookshelfScreen/row components and synthetic cached chapters; check layout/metadata/missing fields, select/deselect/open, dark 320 accessibility, grid unchanged, search/import and navigation. Not real user network/book import E2E. The older iOS26 confirmation Cancel test remains unresolved and is not included in this focused suite.
