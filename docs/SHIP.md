# Shipping La Réplique to TestFlight

**Build path: Xcode Cloud only.** This Mac runs a beta macOS; binaries archived
here fail App Store validation with **ITMS-90111** even with the GA Xcode SDK.
Apple's Xcode Cloud runners are on GA macOS, so that's the sanctioned route
(same as Astheure / L'Accalmie / Le Galet).

## State of the repo (done in code)

- ✅ ClaudeKit **vendored in-repo** at `Vendor/ClaudeKit` — no external local
  package, so the cloud clone is self-contained. (`import ClaudeKit` unchanged.)
- ✅ `LaReplique.xcodeproj` is **committed** (regenerate with `./gen.sh`, then
  commit the diff). Xcode Cloud needs the project + its workflow manifest.
- ✅ iCloud/CloudKit entitlements + `iCloud.app.atelier.lareplique` container,
  per-SDK. Team `9WZ66DZ69J`.

## Steps that need you (Apple login / interactive)

### 1. App Store Connect app record
Bundle id `app.atelier.lareplique` must be registered and an app record created.
- I can do this via the ASC API (your key is in `~/.appstoreconnect` and
  `_outillage/config.env`) — just say go, and confirm the **App Store name**
  (must be globally unique; "La Réplique" may be taken — have a fallback like
  "La Réplique — théâtre").
- Or do it by hand at appstoreconnect.apple.com → Apps → +.

### 2. Enroll Xcode Cloud (one-time, in Xcode)
1. `./gen.sh && open LaReplique.xcodeproj`.
2. Product ▸ Xcode Cloud ▸ Create Workflow. Pick the **LaReplique** scheme.
3. Grant Xcode Cloud access to the GitHub repo `gautjac/la-replique-native`
   when prompted (Apple ID + GitHub auth — only you can do this).
4. Workflow: **Archive – iOS**, action **TestFlight (Internal)**. Branch `main`.
5. Xcode writes `LaReplique.xcodeproj/.../xcodecloud/manifest.json` — **commit
   it** so the workflow config lives in the repo (Astheure does this).

Xcode Cloud auto-signs (managed signing with your team). No local certs needed.

### 3. First build
Push to `main` (or hit "Start Build" on the workflow). ~10–15 min on GA-macOS
runners → the build appears in TestFlight ▸ iOS builds. Add yourself as an
internal tester.

## CloudKit note for TestFlight builds

TestFlight/App Store builds use the **Production** CloudKit environment (Xcode
runs use Development). Before sync works for testers:
- CloudKit Console → container `iCloud.app.atelier.lareplique` → **Deploy Schema
  to Production** (Play/Character/Element/Version + PublicPlay record types).
- For the web viewer to read published plays from a TestFlight build, flip
  `src/lire/cloudkit.ts` `ENVIRONMENT` to `"production"` and grant `PublicPlay`
  **World: Read** in Production (see `docs/CLOUDKIT_SETUP.md` if present).

The app still **opens and persists locally** without any of this (3-tier store
fallback) — CloudKit sync just won't light up until the schema is deployed.

## After any project.yml change
`./gen.sh` → `git add LaReplique.xcodeproj` → commit. The committed project is
the source of truth for the cloud.
