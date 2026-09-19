# Notes on a shared reading (2026-09-19)

Readers leave notes on the published reading (`la-replique.netlify.app/lire/<id>`),
anchored to a line, optionally quoting a few words. Everyone with the link sees
them. The owner reads, replies, resolves and hides from the app. Think Google
Docs comments, on a read-only text.

## The decision that shapes everything

CloudKit's **public** database, with its **default security roles** and nothing
else: everyone reads, any signed-in iCloud user creates, and **only a record's
creator can change or delete it**. So:

| What | Where | Who writes it |
|---|---|---|
| A note or a reply | `PlayComment` record | whoever wrote it (Apple ID sign-in) |
| Author marks own thread resolved | `PlayComment.resolved` | that author |
| Notes open/closed | `PublicPlay.commentsOpen` | the play's owner |
| Owner marks a thread resolved | `PublicPlay.resolvedComments` (string list) | the owner |
| Owner hides a note | `PublicPlay.hiddenComments` (string list) | the owner |

The owner cannot touch other people's records, so the owner's moderation lives on
the owner's own record. No custom roles, no server, no accounts of ours.

`PlayComment` fields: `readingID` (the share id, queryable — NOT named `shareID`: CKQuery reads
that predicate key as CloudKit's system `share` reference and fails with "Unknown field '___share'"), `elementID` (`""` = a general note),
`quote?`, `body`, `authorName`, `parentID?` (replies are one level deep),
`resolved` (Int 0/1). Author identity and time come from CloudKit's own
`creatorUserRecordID` / `creationDate`. Display names are typed by the commenter
(the web stores it in `localStorage`, the app in `notes.authorName`).

## Anchors

- The published JSON now carries each element's `id` (`PlayFormat.aiDoc(withElementIDs:)`).
  The AI/export flavour still leaves ids out.
- `Element.id` is stable across edits and reorders, so « Mettre à jour » keeps
  every note on its line.
- Version snapshots carry ids too and **restore keeps them** (`replaceContent`);
  a fresh import mints new ones. Snapshots saved before 2026-09-19 have no ids —
  restoring one detaches the notes.
- A note whose line no longer exists is **detached**, never lost: it moves to
  « Notes détachées » with its quote. A reply whose root was deleted stands in
  as root. Rules live in `Sources/Models/Comments.swift`, mirrored line for line
  by the web's `src/lire/comments.ts`; `NotesTests` ≙ `comments.test.ts`.

## In the app

- `NotesStore` (one per open play) polls every 60 s while the play is open.
- Margin badge on a line = open threads there (`ElementRow.noteCount`, part of
  the row's Equatable key, so the editor's one-row-per-keystroke shape holds).
- Toolbar « Notes » → `NotesPanel`: open/close notes, sign-as name, threads by
  line (tap the header to jump), general notes, detached notes.
- Library sidebar: unread count per shared play (`NotesInbox`, one pass when the
  app comes forward).
- Turning notes on asks for notification permission and saves a
  `CKQuerySubscription` (`notes-<shareID>`) so a new note pushes an alert.
- `LR_NOTES_DEMO=1` (DEBUG) swaps in `DemoComments`, seeded on the play's first
  lines — how the UI was verified on the simulator.

## One-time CloudKit setup (needs you, in the Console)

Production cannot mint record types, so:

1. `tools/prime-schema.sh` — runs a Debug build on a throwaway store against
   **Development** CloudKit; it now also saves and deletes one `PublicPlay`
   (with the three new fields) and one `PlayComment` in the public database,
   then queries by `readingID` and logs the count (expect 1).
2. CloudKit Console → `iCloud.app.atelier.lareplique` → **Development** → Schema:
   - Record Types → `PlayComment` exists; `PublicPlay` gained `commentsOpen`,
     `resolvedComments`, `hiddenComments`.
   - Indexes → `PlayComment.readingID` is **QUERYABLE** (add it if the log said 0).
   - `PlayComment` also has a stray `shareID` field from the first priming attempt — delete it
     (Development allows that) so it never reaches Production.
   - Security Roles → `PlayComment`: `_world` **Read**, `_icloud` **Create**
     (+ Read), `_creator` **Write** (+ Read). (`PublicPlay` already has `_world` Read.)
3. **Deploy Schema Changes to Production.**
4. Settings → Tokens & Keys → the Production web token: sign-in callback
   `postMessage` (the default), allowed origin `https://la-replique.netlify.app`.

Until step 3 the feature is inert, not broken: old plays have `commentsOpen`
unset, and the app's toggle fails with a clear error.

## Known limits (v1)

- Commenting needs an Apple ID. Reading notes does not.
- Anyone with the link who signs in can write. The owner's tools are hide,
  resolve, and closing notes; there is no per-person block.
- Unpublishing removes the reading and the push subscription; the orphaned
  `PlayComment` records stay in the public database (only their authors can
  delete them). They are unreachable without the share id.
- Web sign-in (Apple's popup) could not be exercised by the build agent — it
  needs a real Apple ID. Everything up to it is verified on `/lire/demo`.
