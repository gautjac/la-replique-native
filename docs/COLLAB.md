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
| 1c. Firestore transport + session + shared-plays store | ✅ `FirestoreTransport`, `CollabSession`, `CollabStore`, `CollabService` (share / invite / join) |
| 1d. Two devices editing one play | ✅ two simulators on the local emulator, both directions + a server-side edit; 16/16 remote changes redrawn |
| 1e. Security rules | ✅ web repo `firebase/firestore.rules`, 13 emulator tests (`npm run test:rules`) |
| 1f. The real Firebase project | ✅ `la-replique-atelier` (the id `la-replique` was taken), Firestore in Montréal, rules + indexes deployed, iOS + web apps registered, `GoogleService-Info.plist` in `Sources/Resources/` |
| 1g. Authentication switched on | ✅ 2026-09-21 — Apple, Google, email; `la-replique.netlify.app` authorised |
| 2a. Sign-in — Apple, Google, email link (`CollabAuth`, `CollabSignInView`) | ✅ built; **email link verified end to end on the Auth emulator**; Apple and Google need a real account on a real build — untested |
| 2b. Presence + soft line lock (`PresenceChannel`) | ✅ two simulators: name + colour on the other person's line, their line can't be focused, typing into it never reaches the server; stale after 45 s |
| 2c. Member list, roles, remove, leave (`MembersStore`) | ✅ built against the tested rules |
| 2d. "The plays I'm in" on every device (`CollabService.syncLibrary`) | ✅ built (collection-group query on `members.uid`); runs on sign-in and on foreground |
| 2e. Landing pages `/connexion` and `/rejoindre/<code>` | ✅ live on la-replique.netlify.app |
| 3. Collaborative web editor (revive `src/App.tsx`) | — |
| 4. Notes on the new backend; history "who wrote what" | — |

### What the fuzz taught (keep)

Deleting a line and, before the next tick, receiving someone's edit to that same
line used to bring it back for good. The engine now ignores upserts for refs it
deleted in the same pass, and the simulated server reports the effect of writes
issued during a delivery (as the real SDK does) — swallowing that is what hid
the bug at five seeds. Soak with
`TEST_RUNNER_LR_FUZZ_SEEDS=400 xcodebuild test … -only-testing:LaRepliqueTests/CollabCoreTests`.

## Two-device smoke test (no cloud project needed)

```bash
# 1. emulators (web repo) — Java is keg-only: the npm script puts it on PATH
cd ~/Claude/apps/la-replique && npm run emulators
# 2. a locally SIGNED simulator build (Firebase Auth needs the keychain; an
#    unsigned CODE_SIGNING_ALLOWED=NO build fails with "error accessing the keychain")
cd ~/Claude/apps/la-replique-native
xcodebuild build -project LaReplique.xcodeproj -scheme LaReplique \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build-signed
# 3. A shares its first play and logs `COLLAB invite <CODE>`; B joins with it
SIMCTL_CHILD_LR_EPHEMERAL=1 SIMCTL_CHILD_LR_COLLAB_EMULATOR=1 SIMCTL_CHILD_LR_COLLAB_AUTOSHARE=1 xcrun simctl launch <A> app.atelier.lareplique
SIMCTL_CHILD_LR_EPHEMERAL=1 SIMCTL_CHILD_LR_COLLAB_EMULATOR=1 SIMCTL_CHILD_LR_COLLAB_AUTOJOIN=<CODE> xcrun simctl launch <B> app.atelier.lareplique
```

To test redraws WITHOUT touching a simulator (taps, typing and even screenshots
force SwiftUI passes and will fool you), PATCH a line through the emulator's REST
API (`Authorization: Bearer owner` bypasses rules) and count `row body` lines in
the DEBUG render log.

Known and accepted: the periodic shadow save (every ~3 s while changes flow)
re-runs the page body; with the lazy page that is a few milliseconds.

## Decisions still Jac's

1. **The Firebase project** — decided 2026-09-21: `la-replique`, Firestore in Montréal, account
   jac@jacgautreau.com. The CLI token had expired; after `firebase login --reauth`: create the
   project + database, deploy rules/indexes, add the iOS+web apps, drop `GoogleService-Info.plist`
   into `Sources/Resources/` (its presence is what turns the feature on in a real build).
2. **Privacy** — shared plays leave the private iCloud store for a server we run:
   privacy policy + App Store privacy label change. Solo plays stay as they are.
3. **Sign-in methods** — decided 2026-09-21: Apple + Google + email link (step 2). Until then the
   emulator uses anonymous accounts, and a real build offers no sharing at all.
