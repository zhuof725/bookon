# Screenshot-style bookshelf

Reference: user screenshots photo_91AB4728.png and photo_2C4A2EB4.png.

- Default three-column cover grid on phone; larger widths add columns. Covers retain a 0.70 width/height ratio, rounded corners and a subtle shadow. A separate rounded title/subtitle panel follows each cover. Actual books and cover URLs are used; no screenshot book data is injected.
- Top row: search / category capsule / more. More presents a compact anchored material panel with Choose Books, Import Books, View (grid/list), and Sort (last read/added/title). Category choices are All / Reading / Unread / Local.
- Grid/list and sort preferences are stored separately in UserDefaults. Existing book JSON, progress, caches, cover files, source definitions and import formats are unchanged.
- Selection never opens a book accidentally. Removal requires an explicit confirmation; existing removal behavior deletes local files only after confirmation. TXT/EPUB import retains the existing document picker and parser.
- Bottom capsule has Bookshelf / Statistics / My. Search is now available from the top-left and My; source management remains under My. Statistics reports actual library counts and existing chapter history, not invented reading time.
- The custom dock is inset into the NavigationStack root content only, not the entire stack. Pushed reading/search/source screens must not retain the dock. Reader menu, typography, pagination and turn mechanics are unchanged.
- Visuals use iOS 16-compatible SwiftUI material. OS material and typography may differ from the reference; screenshot validation is from an offline native fixture, not a pixel-identical or full network end-to-end claim.
