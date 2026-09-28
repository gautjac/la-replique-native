# Craft corpus (native)

The Atelier's craft library — a curated subset of
[jtydhr88/screenwriting-skills](https://github.com/jtydhr88/screenwriting-skills) — ships inside
the app bundle as `Resources/Corpus/` (a folder reference on `Corpus/` in `project.yml`).

- **Source of truth is the web app**: `~/Claude/apps/la-replique/netlify/functions/lib/corpus/`.
  `npm run corpus:sync` there re-vendors from `~/.claude/skills` and **mirrors `Corpus/` here**
  (it deletes and recreates the folder — never edit files in `Corpus/` by hand).
- `Corpus/manifest.json` defines the `core` set (every op) and the per-op `extras`;
  `Sources/AI/Corpus.swift` reads it at runtime and builds the same block layout as the web
  function: core (cached 1h) → extras (cached 1h) → task prompt (uncached).
- The Dramaturge adds a 4th system block: the play itself (`<piece …>`), cached **5 min** and placed
  after the 1h blocks (a shorter TTL must follow the longer ones) — 3 breakpoints in all
  (`Atelier.dramaturgeRequest`). The messages carry only the thread + the new question, so each
  follow-up reads corpus + play from cache instead of re-sending the play at full price.
- `Atelier.tools` is ONE fixed list in a fixed order: tool definitions sit ahead of `system` in the
  cache prefix, so varying them per op would drop the cached corpus on every switch. Only
  `tool_choice` varies.
- BYOK: the cache lives under the user's own key. The console line `atelier <op>: … cache_read=…`
  shows hits; the first call of an hour writes ≈57 K tokens (relance) at 2× input price, each
  following call reads them at ~0.1×.
- Tests: `Tests/CorpusTests.swift` (bundle presence, layout, cache markers, tool order).

Full design, sizes and update procedure: the web repo's `docs/CRAFT_CORPUS.md`.
