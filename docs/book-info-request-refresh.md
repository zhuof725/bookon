# Recovering a saved signed book-detail request

## Why a cover can remain while details fail

The Qimo fixture builds a detail GET URL plus JSON options with QDSign/QDInfo/tstamp headers while parsing search results. These are evaluated values, not a signing recipe. Book Codable saves that string. AnalyzeUrl can evaluate remaining templates, but replaying already-expanded headers does not refresh them. The earlier cover fix correctly retained valid saved covers when details failed, but it did not renew requests.

This mechanism is confirmed in code; the user's screenshot alone does not identify the server's exact HTTP status or prove its signing lifetime.

## Recovery policy

For an eligible saved HTTP(S) GET request with explicit JSON headers and a dynamic source search bookUrl rule, an actual HTTP 401/403 triggers one search against the same source using the saved book name. Accept exactly one candidate whose source ID, trimmed Unicode-normalized name and author, method, no-body policy, and full transport URL (including query) match. Headers must have changed. Query parameters are never dropped to guess a book ID.

Fetch that candidate once using its complete freshly generated options. The response must be HTTP 2xx and its actual parsed name/author must match the saved book. Empty/error 200 bodies cannot pass by falling back to the saved name. Parsing starts from the original Book so bookUrl/origin, dates and reading position remain stable. Candidate book variables are pending and only bound to the original identity after success.

The saved bookUrl is deliberately not replaced with the new signed URL: shelf lookup, cache keys, detail metadata and SwiftUI task identity use it. Each later opening may require another bounded recovery; this is not a permanent signature cache or token migration.

## Limits and failure behavior

No hardcoded signer, credentials, query-ID extraction, source switching, or new Book persistence fields. No recovery search for 404/429/5xx or transport failure. Only strict JSON header options (as produced by JSON.stringify in Qimo) qualify; loose single-quoted options remain executable but are not automatically renewed. Unsupported POST/body, query-signed URLs, missing/mismatched author/name, ambiguous results, failed searches, repeated rejection or invalid renewed details are reported instead of guessed. Reading progress and existing cover remain intact.

The bounded signed-request path defers the existing browser challenge fallback only for the eligible initial HTTP 401/403. Recovery search/retry are native and bounded; ordinary requests and the initial request's other statuses keep the existing policy. Error messages expose HTTP status and a Chinese explanation, never request headers/options or response bodies. Genuine source login/security challenges still require source updates or user login; renewal is not a bypass.

## Validation

Use production WebBook/AnalyzeUrl with an injected URLSession/URLProtocol. Real Qimo signing rules plus synthetic book metadata demonstrate that old headers are replayed while re-search regenerates them; no live endpoints or user credentials are required. Regression must cover success, stable Book Codable identity/progress, mismatches/duplicates, request counts, errors, cancellation, variable isolation and the previous cover guards. Release compilation verifies application integration. This does not claim the user's private source instance was reproduced on-device.
