# Source-book cover after reopening from the shelf

Reported with 柒墨中文 / 青山: a cover is visible in search or the first details visit, but disappears when opening the saved book again. The checked-in related fixture is named 柒默中文.

The fixture's detail cover rule constructs a Yuewen URL using `{{$.Data.BookId}}`. `getString` legitimately substitutes an empty value when the response has no BookId. This produced `https://bookcover.yuewen.com/qdbimg/349573//600`, a nonempty string that `WebBook.parseBookInfo` accepted as a replacement for the saved cover. A detail error/partial response could therefore turn a valid saved cover into a broken image when reopening. Book Codable already includes coverUrl; the field was not lost by bookshelf serialization.

The fix adds `AnalyzeRule.getCoverString`, used only for search and detail cover fields. Literal cover templates with missing/null/undefined substitutions in their URL address are treated as absent. Ordinary `getString` keeps its original semantics. Templates in optional query/fragment/request options remain optional, and a subsequent JS stage can still supply an explicit fallback. Normal nonempty updated cover URLs continue to replace the previous URL.

`WebBook.bookInfo` now checks known HTTP status before parsing metadata: non-2xx errors throw so the detail coordinator retains the prior book. Unknown status 0 from existing data/WebView paths stays supported. This does not refresh source-specific signed requests, change cookies/headers, or claim to repair the source's own API availability.

Validation uses the production Qimo rule with synthetic JSON and book IDs, a JSON-serialized/reloaded Book, empty/partial/error detail bodies, valid updates, and compatible CSS/JSON/JS rules. An injected URLSession/URLProtocol tests the actual request-to-bookInfo path for valid responses, HTTP errors, and transport failure. These are deterministic fixtures, not the user's private source configuration or a device reproduction of the complete novel.

Existing saved valid covers are retained automatically when reopening. This does not invent cover URLs for books whose source never supplied a valid cover.
