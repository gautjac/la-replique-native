# Vendored ClaudeKit

This is a **verbatim copy** of the `ClaudeKit` product from the shared
`AtelierKit` package (`~/Claude/apps/atelier-kit`). It is vendored here so
La Réplique builds on **Xcode Cloud**, which clones only this repo and cannot
reach the sibling `../atelier-kit` local package (AtelierKit has no git remote).

- **Canonical source:** `~/Claude/apps/atelier-kit`, target/product `ClaudeKit`.
- **Vendored from revision:** `044751a` (2026-09-12) — adds `systemBlocks` + `ClaudeCacheControl` for the craft corpus;
  refreshed 2026-09-28 to `540beb4`, the prompt-caching changes:
  sorted-keys encoding (tool schemas byte-stable across launches), top-level +
  per-tool `cache_control`, streaming usage (`stream(_:onUsage:)`), `ClaudeModel.minimumCacheablePrefixTokens`.
- **Contents:** `ClaudeClient`, `ClaudeError`, `ClaudeModel`, `ClaudeResponse`,
  `ClaudeTypes`, `JSONValue`, `KeychainStore`. Only imports `Foundation` and
  `Security` — no sibling-kit dependencies.

## Refreshing after upstream changes

```sh
cp ~/Claude/apps/atelier-kit/Sources/ClaudeKit/*.swift \
   Vendor/ClaudeKit/Sources/ClaudeKit/
# then update the revision line above to `git -C ~/Claude/apps/atelier-kit rev-parse --short HEAD`
```

Keep this in sync by hand when ClaudeKit changes upstream. If AtelierKit ever
gains a git remote, prefer switching back to a versioned package reference in
`project.yml` and deleting this vendored copy.
