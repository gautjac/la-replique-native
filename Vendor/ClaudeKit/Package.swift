// swift-tools-version: 6.0
// ClaudeKit — vendored, self-contained copy of AtelierKit's ClaudeKit product.
//
// Why vendored: La Réplique ships via Xcode Cloud, which clones only this app
// repo. AtelierKit lives at ../atelier-kit (a local-only package, no git remote),
// so a path reference outside the repo can't resolve on Apple's build runners.
// Vendoring ClaudeKit in-repo keeps the build fully self-contained.
//
// Canonical source: ~/Claude/apps/atelier-kit, product "ClaudeKit"
// (Anthropic Messages API client + BYOK Keychain helper; macOS + iOS).
// See Vendor/ClaudeKit/PROVENANCE.md for the revision this was copied from and
// how to refresh it.
import PackageDescription

let package = Package(
    name: "ClaudeKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ClaudeKit", targets: ["ClaudeKit"]),
    ],
    targets: [
        .target(name: "ClaudeKit"),
    ]
)
