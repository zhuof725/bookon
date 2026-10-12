# EPUB cover persistence and lifecycle

Reported symptom: EPUB cover disappears after backgrounding or reopening.

Two app-owned weaknesses were identified in source: persisted coverUrl contained the absolute iOS container path; local cover tasks cleared an existing bitmap before each read and never retried after foreground/protected-data availability. BookRow also used network AsyncImage for file URLs.

- New EPUB imports store `legado-cover://local/<existing MD5 bookURL>/cover.img`, not a container UUID path. Cover bytes remain under Documents/LocalBooks, written atomically; save failures are no longer silently accepted.
- Existing local bookshelf records migrate on load, retaining book URL, chapters and reading progress. Current book identity resolves the cover from the current Documents directory, including snapshots with old absolute paths. No book reimport or deletion is needed when cover.img still exists.
- Shelf, detail, list and reader cover controls share the same local ImageIO thumbnail loader. Local files do not go through AsyncImage; remote covers still do.
- Same-URL retries keep the last valid bitmap until a new decode succeeds. Cancellation and transient file-access failure do not blank it. Different URLs clear previous book imagery; generations prevent stale asynchronous completions overwriting newer requests.
- Foreground and protected-data-available events retry local loading. Recreated views and fresh app processes reload from the persistent file.

This cannot recreate a cover file already missing from the app's Documents directory, nor restore deleted EPUB content. No claim of reproducing the user's exact book/device without receiving it. Targeted tests use generated PNG covers in a sandbox, stale path rebasing, file failures/cancellation, background/foreground and process relaunch. EPUB parsing itself, reader typography and pagination are unchanged.
