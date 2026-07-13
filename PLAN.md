# La Réplique — universal native app

Turning the web app ([la-replique.netlify.app](https://la-replique.netlify.app),
`~/Claude/apps/la-replique`) into a universal SwiftUI app. **Native is the product;
the web becomes a read-only window onto it.**

## Locked decisions
- **BYOK** — the Anthropic **and** ElevenLabs keys live in the Keychain via ClaudeKit's
  `KeychainStore`. No server; a light first-run key screen gates the AI/TTS surfaces.
- **Universal from day one** — one SwiftUI multiplatform target: **iPhone · iPad · Mac**
  (visionOS optional later).
- **SwiftData + CloudKit (private DB) + iCloud sync** across the user's devices, from P0.
- **Web = read-only.** "Publier — lecture seule" per play → a shareable
  `la-replique.netlify.app/lire/<id>` link (public CloudKit record, read via CloudKit JS).
- **Interchange bridge:** the `la-replique/1` JSON format already carries plays losslessly
  between web and native — import/export both directions.

## Location & tooling
- Build in **`~/Claude/apps/la-replique-native/`** (never iCloud — corrupts signing).
- **XcodeGen** (`project.yml` + `gen.sh`) + `run-mac.sh` / `install-device.sh`, cloned from
  **Le Découpage**'s layout (the atelier's proven native-script-editor project).
- Depend on **ClaudeKit** (local SPM: `.package(path: "../atelier-kit")`).
- (Eventually native may take the clean name `la-replique` and the web repo become
  `la-replique-web`, mirroring `l-accordeur` / `l-accordeur-web` — deferred to avoid churn.)

## Architecture
`NavigationSplitView` that adapts per platform:
- **Mac / iPad:** plays sidebar → script editor → inspector (cast · beats · measures · Atelier).
- **iPhone:** navigation stack; inspectors are sheets.

Reuse map:

| Reuse (already built) | Rebuild in Swift |
|---|---|
| `la-replique/1` JSON model + import/export | The UI (React → SwiftUI) |
| **ClaudeKit** (AtelierKit): Anthropic client, SSE stream, structured output, BYOK Keychain | Storage (Dexie → SwiftData + CloudKit) |
| The AI prompts (relance/dramaturgie/voix/etsi/traduire/retouche) | Editor input engine |
| **Le Découpage** project scaffold + editor patterns | Beat board / cast / measures views |
| **L'Outillage** (`doctor`/`ship-ios`/`ship-mas`/`ship-mac`) | Print layouts (native) |
| **Conduite AI** doctrine + `evals/goldens.md` | TTS (Web Speech/ElevenLabs → AVSpeech/ElevenLabs) |
| The promo video → App Store preview | — |

## Data model (SwiftData + CloudKit)
CloudKit-safe: every attribute optional/defaulted, **no `@Attribute(.unique)`**, relationships
optional (same discipline as the web data-durability rule).
- `Play { id, title, subtitle, author, lang, altLang, createdAt, updatedAt, [Character], [Element] }`
- `Character { id, name, colorHex, note, voiceID }`
- `Element { id, order:Int, kind:String, characterID?, text?, label?, setting?, synopsis?, beat?, parenthetical?, alt? }`
  — one model with a `kind` discriminator (SwiftData dislikes polymorphic unions; this mirrors
  the JSON 1:1 and imports cleanly).
- Sync = CloudKit **private** DB via SwiftData. Versions = snapshot models.

## The editor (the crux — spike first)
Keyboard flow: Enter = new réplique · Tab = convert type · name+space = switch speaker.
- **Mac / iPad-with-keyboard:** list of element rows, `@FocusState` enum for focus movement,
  `.onKeyPress(.tab)` / `.onSubmit` / text-watching for type-ahead. **Reuse Le Découpage's editor.**
- **iPhone (touch):** same model, keyboard-accessory toolbar (＋Réplique · Didascalie · Scène ·
  Personnage▾); Return = new line.
- **iPad bonus:** Apple Pencil Scribble + margin notes.
- *Mitigation:* if SwiftUI focus/key handling is too fiddly, drop to a `UIViewRepresentable` /
  `NSViewRepresentable` text engine for rows. **Prototype in P1 before committing.**

## Atelier AI — BYOK via ClaudeKit
- First-run key screen stores Claude (+ ElevenLabs) keys in Keychain (`KeychainStore`).
- Six surfaces port verbatim from the web prompts: **relance · dramaturgie · voix · et si ·
  traduire · retouche** (inline). NDJSON→SSE streaming maps onto ClaudeKit's stream; keep the
  draft-not-verdict UI (« ébauche · à toi de décider »).
- `evals/goldens.md` carried over; re-run before any model bump (Conduite AI).
- *Optional later:* on-device **Apple Foundation Models** for relance/dramaturgie (free, offline,
  private) with a ClaudeKit fallback — a hybrid layer, not required for v1.

## Table-read / TTS
- **Système** → `AVSpeechSynthesizer`, distinct `AVSpeechSynthesisVoice` per character (offline).
- **ElevenLabs** → BYOK key; the `voiceID`-per-character picker ports directly.
- (Respect the preview-audio caution when testing on the real Mac.)

## Web-readability — "share-a-link" (chosen)
1. Library lives in the CloudKit **private** DB (SwiftData) — the user's sync.
2. Per play, **"Publier — lecture seule"** writes one clean `CKRecord` — the play as
   `la-replique/1` JSON — to the CloudKit **public** DB under a random `shareID`
   (`PublicPlay { shareID, json, title, updatedAt }`). Direct `CKDatabase` write, *not*
   SwiftData, so the schema is clean and ours.
3. Returns `la-replique.netlify.app/lire/<shareID>`.
4. The **existing web app** gains a read-only `/lire/:id` route that fetches the public record
   via **CloudKit JS** (container + read-only API token; public reads need no iCloud login) and
   renders the play with the components already built — same fonts/colours/cues/beats.
5. Unpublish deletes the record.
- *Phase-2 option:* a full **private library** web viewer via **Sign in with Apple** + CloudKit JS
  (browse all your plays read-only) — same plumbing, add auth + private DB query.

## Feature parity (all maps)
Editor · cast + presence grid + **doubling** + **through-line** · **beat board** (SwiftUI
`.draggable`/`.dropDestination`) · Atelier (5 tools + inline retouche) · bilingual UI (String
Catalog `.xcstrings`) + per-play language · table-read · surtitles · sides · versions · print
(clean + théâtre via `NSPrintOperation`/`UIPrintInteractionController` + PDFKit) ·
import/export (`la-replique/1` + plain text; DocumentPicker + ShareLink). Native wins: Shortcuts,
widgets, Handoff, keyboard shortcuts, Quick Look.

## Phases
- **P0 — Scaffold (½–1 day):** XcodeGen universal target off Le Découpage; ClaudeKit dep;
  SwiftData+CloudKit container + iCloud/CloudKit entitlements; app shell (split view); JSON
  importer to seed real plays. First-run key screen.
- **P1 — Data + editor spike (2–3 days):** models; keyboard-flow editor on Mac/iPad; iPhone
  toolbar variant. *Highest risk — do first.*
- **P2 — Cast / board / measures (1–2 days).**
- **P3 — Atelier AI, BYOK ClaudeKit (1–2 days):** prompts + streaming + draft UI; goldens.
- **P4 — Table-read / TTS (1 day).**
- **P5 — Import/export/print/versions (1–2 days).**
- **P5.5 — Web viewer — ✅ DONE.** Native `Publish` service (publish/mettre-à-jour/dépublier →
  `PublicPlay` record, `recordName == shareID`, public CloudKit DB) + `PublishView` sheet wired
  into the ••• menu; `Play.publicShareID`. Web app: `/lire/:id` route + `src/lire/{cloudkit,Lire}`
  (CloudKit JS read via origin-restricted web token `VITE_CLOUDKIT_TOKEN` in Netlify env). Live &
  verified at `la-replique.netlify.app/lire/demo`. 3 PublishTests (25 total green, iOS+macOS).
  **Deploy-time gap (needs a signed native build to exercise):** on first publish, dev CloudKit
  auto-creates the `PublicPlay` type; then grant the record type **World: read** in the CloudKit
  dashboard so the web token can read it. The web viewer points at the **development** environment.
- **P6 — Polish — mostly ✅.** Done: App Intents/Shortcuts (`NewPlayIntent`, `PublishPlayIntent`,
  `PlayEntity` picker, Siri/Spotlight phrases FR+EN) + `AppRouter`; first-run `OnboardingView`
  (`hasOnboarded`); **Conduite AI 9-category walk → `CONDUITE.md`** (no gaps — prompts already carry
  no-flattery, never-invent, delimited untrusted content; wait is staged; goldens in place).
  Deferred to ship-time / needs Jac's call: **EN String Catalog** (app is FR-first; SwiftUI `Text`
  already extracts to `Localizable.xcstrings` when we commit to translating), **PencilKit** (iPad
  Scribble already works for free in the text fields; annotation layer is optional).
- **P7 — Ship (1 day):** bundle ids + iCloud/CloudKit entitlements; **register extension bundle
  ids via ASC API first**; **Xcode Cloud on GA macOS** (dodges ITMS-90111); **real-device build**
  (sim-green hides device-only framework errors); TestFlight → App Store; promo video as preview.

**≈ 2.5–3 focused weeks to a TestFlight-quality universal app**, web viewer included.

## Shipping rig
`_outillage/doctor.sh` first; `ship-ios.sh` (TestFlight) and `ship-mas.sh` (Mac App Store).
macOS App Store builds via **Xcode Cloud on a GA macOS** (the beta-macOS ITMS-90111 trap).
Team `9WZ66DZ69J`.

## Risks & mitigations
1. **Editor keyboard flow across platforms** — spike P1, reuse Le Découpage, representable fallback.
2. **SwiftData+CloudKit constraints** — optional/defaulted model; **retain the `ModelContainer`
   in tests** (the EXC_BREAKPOINT trap).
3. **CloudKit web schema** — keep the public `PublicPlay` record clean and app-managed (not Core
   Data's mirrored schema).
4. **macOS beta signing** — Xcode Cloud GA builds.
5. **Scope** — phase it; universal is fine from day one with SwiftUI multiplatform.
