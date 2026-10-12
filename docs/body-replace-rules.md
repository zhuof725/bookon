# Body replacement rules

My → Library Management → Replacement Rules (我的 → 替换规则).

Rules apply to **reading body display only**. Literal and regex modes, replacement (empty deletes), per-rule enable switch, name, test preview, add/edit/delete with confirmation are supported. Rules run in saved list order, and regex replacements support Foundation capture templates such as `$1`; literal replacements preserve `$` and backslashes.

The reader captures an immutable rule snapshot on entry. Exit and re-enter reading after changing rules; no old book needs reimporting. Foreground load, paged neighbor preparation, and continuous-scroll neighbor loading all share the same snapshot. Replacement occurs after parsing source markup, separately per paragraph. Images, link targets, comment counts, chapter titles, volume titles, original files and raw cache are untouched. Search and speech use the displayed content, as does pagination. Changed text length can change page count; saved progress continues using the existing approximate within-chapter percentage. An empty plain chapter after filtering shows a short empty-state message instead of a broken reader.

At most 50 rules; names ≤60 characters, pattern ≤512 UTF-16 units, replacement ≤2000 units. Invalid syntax/empty patterns cannot be saved. A paragraph longer than 1,000,000 UTF-16 units is left unchanged; bounded expansion and cooperative Foundation matching cancellation prevent partial replacements on timeout/limit. This is not a preemptive regex sandbox.

Built-in TXT TOC rows are now static labels with no button, editing sheet, test sheet or context-menu action. Custom TXT rules remain editable. Bundled parser behavior is unchanged. All new screens use existing monochrome AppPalette; no theme changes.
