# La Réplique (native) — Atelier goldens

Model pinned in one place: `Atelier.run(... model: .opus ...)` (ClaudeModel.opus →
`claude-opus-4-8`). BYOK — needs the user's Anthropic key in the Keychain. Before bumping the
model, run these against a real key and eyeball the qualities. Same prompts as the web app,
so the web `evals/goldens.md` applies verbatim; the essentials:

1. **Relance (FR)** — Alice, after Bruno's line. FR, in Alice's evasive voice, an active move, one
   step (not a resolution), `line` = spoken words only.
2. **Dramaturgie (FR)** — a flat scene → names the problem, no flattery, ≥1 `tension` point, ≥1
   `piste`, clean French (no franglais).
3. **Voix (FR)** — plant one over-formal line among clipped ones → flagged as a register break;
   consistent input → empty `points`.
4. **Et si (FR)** — 3 concrete complications specific to the characters, each raising stakes.
5. **Traduire (FR→EN)** — every key returned (fallback keeps untranslated lines), playable English,
   proper nouns kept, keys unchanged.
6. **Retoucher (tighten)** — 3 shorter variants, same intent/voice, `note` explains the cut.

7. **Craft corpus present, invisible, cached** — every op sends the vendored screenwriting
   skills (`Corpus/`, same `manifest.json` as the web app) as two cached system blocks ahead of
   the task prompt, plus ONE fixed tool list (tools are part of the cache prefix). Run relance
   twice, then dramaturgie: the Xcode console prints `atelier relance: … cache_read=≈57000` on
   the second call and `atelier dramaturgie: … cache_read=≈36000` (the shared core) right
   after. Output stays in the scene's language — no Chinese, no book or author names, no craft
   lecture; the read is sharper (wants, tactics, on-the-nose lines, where the value turns),
   not longer. See `docs/CRAFT_CORPUS.md`.

8. **Dramaturge (threaded Q&A)** — « Toute la pièce » or one scene; starter chips when empty,
   follow-up chips after each answer; the thread survives switching tools inside the sheet and
   is dropped when the sheet closes. Same qualities as the web §11: answers THE question about
   THESE pages, quotes real fragments, offers readings not orders, `followups` specific to the
   play, no invented off-page facts, no flattery, no Chinese. Console on Q2: `cache_read` ≈ 86 K.

Run via the Atelier sheet with a key set, or unit-test the pure prep (`Atelier.scriptText`,
`Translate.buildBundle/makeTranslatedPlay`, result-struct decoding) — see `Tests/AtelierTests.swift`.
