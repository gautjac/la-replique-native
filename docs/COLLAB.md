# Collaborative plays — design and status

**Decision (2026-09-21, Jac):** La Réplique becomes collaborative "like a Google
Doc". Some collaborators are not on Apple devices; two people rarely type in the
same line at the same moment. So: **line-level real-time sync on a hosted
backend (Firebase)**, not CloudKit sharing (Apple-only, SwiftData can't) and not
a character-level CRDT (a server and permissions to build ourselves, for a case
that barely occurs here).

Branch `collab` in both repos. `main` stays shippable.

## Shape

```
 editor (unchanged) ──reads/writes──▶ SwiftData objects ◀──applies── CollabCore ◀── transport ◀── Firestore
                                             └──────diff vs shadow──▶ ops ─────────▶ transport ──▶
```

The editor never learns a play is shared. `CollabCore` sits beside it:

- `flushLocal()` — diff the local play against the **shadow** (the last state
  both sides agreed on, per entity, per field) → field-level ops.
- `applyRemote()` — flush first (what I typed is "mine"), then apply "theirs",
  then renumber the local dense `order` from the agreed keys.
- The shadow is persisted, so every merge is three-way even after a relaunch or
  a day offline.

Rules: different fields of one line both win; the same field is
last-writer-wins; **delete beats edit** (a patch must fail on a missing doc,
never resurrect it); a removed character's lines stay, unassigned.

### Order

Locally `Element.order` is a dense Int renumbered on every insert — two writers
would rewrite and collide on every row. Shared plays carry a string `orderKey`
(`FractionalIndex`, twin in the web's `src/collab/fractionalIndex.ts`, identical
vectors). Appending steps a fixed-width head (5000 lines written at the end →
4-char keys); a gap is split 1/8 in (300 lines written into one gap → 13 chars);
past 40 chars the list is re-spread once. On a reorder only the moved block gets
a new key (longest-increasing-run of the existing keys is kept). Equal keys (two
inserts into one gap at the same instant) sort by element id, identically
everywhere, and one of the pair is re-keyed on the next flush.

`orderKey` lives in the shadow and on the server only — **no SwiftData schema
change**, so no private-CloudKit schema deploy.

### Transport contract

`RemoteChange`s arrive in server order and describe server state **overlaid with
this client's own unacknowledged writes** — Firestore listener semantics. That
is what keeps a line from snapping back to an older value while you type. Any
other transport must provide the same.

## Firestore layout (planned)

```
plays/{playID}                        title, subtitle, author, logline, lang, altLang,
                                      ownerUid, members: { uid: "writer" | "commenter" | "reader" },
                                      updatedAt
plays/{playID}/characters/{uuid}      name, color, note, voiceID, order
plays/{playID}/elements/{uuid}        kind, characterID, text, label, setting, synopsis, beat,
                                      parenthetical, alt, orderKey
plays/{playID}/presence/{uid}         name, color, elementID, typing, lastSeen   (heartbeat 20 s, stale after 45 s)
plays/{playID}/notes/{uuid}           (the notes feature moves here — same rules as Comments.swift)
invites/{token}                       playID, role, createdBy, expiresAt
```

Element and character ids are the app's UUIDs, identical on every device — notes
stay anchored. Patches are `updateData` (fails on a missing doc), creations are
`setData`.

Rules, first draft:

```
match /plays/{play} {
  function role() { return get(/databases/$(database)/documents/plays/$(play)).data.members[request.auth.uid]; }
  allow read:   if request.auth != null && role() != null;
  allow update: if role() == "writer" && request.resource.data.members == resource.data.members
             || resource.data.ownerUid == request.auth.uid;
  match /{col}/{doc} {
    allow read:  if role() != null;
    allow write: if (col in ["elements", "characters"] && role() == "writer")
                 || (col == "notes" && role() in ["writer", "commenter"])
                 || (col == "presence" && doc == request.auth.uid && role() != null);
  }
}
```

## Where shared plays live locally

NOT in the iCloud-mirrored store: a shared play reaching the owner's other
devices by two roads (iCloud and Firestore) would let a stale iCloud copy
overwrite a newer line and push that regression to everyone. Shared plays get a
**second, local-only `ModelContainer`** (same model classes). Views already take
their context from the environment, so a shared play's detail view just gets
that container injected; the library shows a « Partagées » section from it.
Sharing a solo play = copy it across (same ids), then remove the private one.

## Status

| Step | State |
|---|---|
| 1a. Fractional ordering (Swift + TS twins) | ✅ `FractionalIndexTests`, `fractionalIndex.test.ts` |
| 1b. `CollabCore` + convergence proof | ✅ `CollabCoreTests`: 15 scenarios + fuzz (3 writers, offline, relaunch) — 405 seeds green |
| 1c. Firestore transport + session (tick, persistence of the shadow) | next — needs the Firebase SDK and a project |
| 1d. Two devices editing one play | next — Firestore emulator needs Java on this Mac, or a real project |
| 2. Sign-in, invitations, roles, presence + soft line lock | — |
| 3. Collaborative web editor (revive `src/App.tsx`) | — |
| 4. Notes on the new backend; history "who wrote what" | — |

### What the fuzz taught (keep)

Deleting a line and, before the next tick, receiving someone's edit to that same
line used to bring it back for good. The engine now ignores upserts for refs it
deleted in the same pass, and the simulated server reports the effect of writes
issued during a delivery (as the real SDK does) — swallowing that is what hid
the bug at five seeds. Soak with
`TEST_RUNNER_LR_FUZZ_SEEDS=400 xcodebuild test … -only-testing:LaRepliqueTests/CollabCoreTests`.

## Decisions still Jac's

1. **The Firebase project** — create `la-replique` (Firestore in
   `northamerica-northeast1`, Montréal) under which Google account?
2. **Privacy** — shared plays leave the private iCloud store for a server we run:
   privacy policy + App Store privacy label change. Solo plays stay as they are.
3. **Sign-in methods** — Sign in with Apple is mandatory on iOS once any other
   provider is offered; plus Google and/or email link for the non-Apple people.
