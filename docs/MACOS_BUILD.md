# macOS host application

The macOS deliverable supports Apple Silicon and macOS 13.5 or later. It uses
Flutter for the complete control surface, `mdd-hostd` for native supervision,
and a Lima `vz` VM for the unchanged Linux/Docker gateway.

The app is distributed directly rather than through the Mac App Store. A sandboxed
App Store process cannot supervise the bundled helper, Lima VM, installer, and
hardware bridge required by this product.

## Local build

On an Apple Silicon Mac with Flutter, Rust, Xcode, and a reviewed Lima binary:

```sh
MDD_LIMA_BIN=/path/to/limactl ./tools/build-macos-app.sh
```

The script builds the Rust helper for `aarch64-apple-darwin`, builds the Flutter
app, and stages the helper, VM template, Lima CLI, and public gateway source into
the application bundle. The v1.0.0 Release applies an ad-hoc signature and does
not use Apple notarization, so Gatekeeper may require explicit user approval.

Starting with v1.0.1, `tools/sign-macos-app-adhoc.sh` explicitly re-signs every
nested Mach-O and code bundle from the deepest component outward before signing
the host app. It then rejects any component that retains a third-party Team ID.
`tools/smoke-macos-app.sh` launches the packaged executable for five seconds on
the Apple Silicon CI runner to catch `dyld` and Library Validation failures.

v1.0.2 additionally carries the documented
`com.apple.security.cs.disable-library-validation` Hardened Runtime exception and
runs the smoke test through LaunchServices/`launchd`, matching a Finder launch on
newer macOS versions.

v1.0.4 bundles an expanded, self-contained Ubuntu 24.04 Lima base template and
validates the final rendered VM configuration with the bundled `limactl`. The
installed App no longer depends on Homebrew's external Lima template directory.

`tools/configure-apple-release-signing.sh` remains available for an optional
future Developer ID signed and notarized distribution.

The VM forwards only HTTPS management port 8443 and the bounded WebRTC WSS range
8089-8139 to the LAN. It never exposes the Docker daemon or socket.
