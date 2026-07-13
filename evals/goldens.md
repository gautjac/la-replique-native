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

Run via the Atelier sheet with a key set, or unit-test the pure prep (`Atelier.scriptText`,
`Translate.buildBundle/makeTranslatedPlay`, result-struct decoding) — see `Tests/AtelierTests.swift`.
