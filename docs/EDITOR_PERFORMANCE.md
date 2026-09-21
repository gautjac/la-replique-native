# Editor performance — how it is measured, and what was fixed (2026-09-12)

Jac reported the app as "a little sluggish". The cause was structural: every
block of the script was built inline inside `PlayEditorView`'s body, in one
non-lazy `VStack`. So any keystroke anywhere re-sorted the play and rebuilt
every row, and any environment change (window activation, keyboard, resize)
did the same.

## Measuring

Two DEBUG-only hooks (`Sources/Models/Bench.swift`):

- `RenderCounter` logs one line per editor page body / row body / binding write
  under subsystem `app.atelier.lareplique`, category `render`.
- `LR_BENCH=<n>` (env var) seeds a synthetic play "Banc d'essai" with `n`
  elements. On the simulator: `SIMCTL_CHILD_LR_BENCH=1500 xcrun simctl launch …`.
- `LR_EPHEMERAL=1` uses a throwaway in-memory store — for driving a Debug build
  on a developer Mac without opening (or syncing) the real library.

Stream the log while typing:

```bash
xcrun simctl spawn booted log stream --level debug --style compact \
  --predicate 'subsystem == "app.atelier.lareplique" AND category == "render"'
```

## Numbers — iPhone 16 Pro simulator, 1500-element play, typing 3 characters

| | page bodies | row bodies | wall time |
|---|---|---|---|
| before | 2 | 3003 | ~5 s (a single 1500-row pass took 1.5–4 s) |
| after | 0 | 3 (one per keystroke) | 13 ms |

Environment-change pass (activation / keyboard): before 3 × 1500 rows ≈ 1.5 s
per pass; after 3 page bodies + 7 rows in 50 ms. App launch with the bench
play: 1504 log lines → 12.

## What changed

1. **One view per block** (`ElementRow`). Observation now scopes a keystroke to
   the row whose `Element` changed. Rows are `Equatable` on `(element id, play
   id, speaker hint)` so a parent pass (focus or hint change) skips unchanged rows.
   The key uses the model UUIDs, not object identity — SwiftData does not keep
   object identity stable across faults.
2. **`LazyVStack`** for the page. Only on-screen blocks exist as views; a
   1500-line play no longer instantiates 1500 text fields. The beat-board jump
   scrolls first, then focuses on the next run-loop tick, so the target row
   exists before it is focused.
3. **`Play.touch()` coalesces** to one `updatedAt` write per second. It is called
   on every keystroke; each write re-ran the library's `@Query(sort: \.updatedAt)`
   and re-rendered every sidebar row.
4. **Lazy export payloads** (`PlayExport: Transferable`). The toolbar held
   `ShareLink(item: Exports.aiJSONString(play))`, which serialised the whole play
   on every toolbar build *and* subscribed the detail view to every line's text —
   so each keystroke re-rendered the detail view, the editor and the page.
5. Single-element lookups (`focusedElement`, Tab-cycle, new-character alert) no
   longer sort the whole play to find one element.

## 2026-09-21 — the Equatable skip was removed

Item 1's `Equatable` rows predate item 2's `LazyVStack`. With a lazy page a parent
pass re-runs only the on-screen rows, so the skip bought nothing — and shared
plays now receive changes from outside the view tree, where a skipped body is the
wrong risk to carry. Keystroke cost is unchanged (Observation still scopes it to
one row). Also: `CollabSession.status` is assigned only on change; re-publishing
it per snapshot re-ran the page body for every remote edit.

## Gotchas learned

- `Equatable` on a SwiftUI view under Swift 6: `==` is nonisolated and cannot
  read the view's main-actor properties. Keep a `Sendable` key and compare that.
- `sips -Z 600` scales the *longest* side. Portrait simulator screenshots come
  out 600 px tall, so tap coordinates derived from them were off by 2×.
- `xcodebuild test` on the same simulator kills and reinstalls the app under test.
