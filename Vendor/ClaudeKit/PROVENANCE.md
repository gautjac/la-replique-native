# Vendored ClaudeKit

This is a **verbatim copy** of the `ClaudeKit` product from the shared
`AtelierKit` package (`~/Claude/apps/atelier-kit`). It is vendored here so
La Réplique builds on **Xcode Cloud**, which clones only this repo and cannot
reach the sibling `../atelier-kit` local package (AtelierKit has no git remote).

- **Canonical source:** `~/Claude/apps/atelier-kit`, target/product `ClaudeKit`.
- **Vendored from revision:** `9f1eacd` (2026-07-13).
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
