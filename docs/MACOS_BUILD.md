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

v1.0.5 expands the complete VM configuration into one self-contained Lima YAML
at build time and validates the final source-mounted configuration with the
bundled `limactl`. The installed App has no runtime base-template locator or
dependency on Homebrew's external Lima template directory.

v1.0.6 preserves Lima's upstream `<prefix>/bin` and `<prefix>/share/lima`
layout inside the App and bundles the matching Linux-aarch64 guest agent. The
macOS smoke test validates its gzip stream and ELF header before accepting a DMG.
The previous `Contents/Resources/limactl` entry point remains as an internal
compatibility link so an already-running v1.0.5 helper survives an in-place App
upgrade.

v1.0.7 signs the bundled `limactl` with Lima's required network-client,
network-server, and virtualization entitlements. CI extracts and audits those
entitlements after signing, then attempts to create, boot, enter, and remove a
temporary 2 GiB VZ Linux-aarch64 VM. A hardware-capable Mac must complete the
boot; GitHub-hosted macOS may skip only the exact
`Virtualization is not available on this hardware` gate after VZ initialization.
The minimal runtime smoke stays separate from validation of the production
8 GiB template.

v1.0.8 treats a running VM with an unavailable gateway as an incomplete install
and idempotently reconciles it instead of waiting without action. The App and
helper negotiate host-service protocol 2, safely replace a legacy listener on
upgrade, and stage gateway source by native App version. Timeout diagnostics use
a bounded 200-line log snapshot rather than a blocking follow.

v1.0.9 implements the hardware bridge previously reserved by the architecture.
The native helper reads the first inserted card through macOS PC/SC and relays
the official VPCD framing over Lima port 32512, forwarded on host loopback only.
The guest builds and registers a separately isolated one-slot `libifdvpcd`, so
the Mac reader cannot alias modem slots or create duplicate card devices.

v1.0.10 uses the non-data-protection macOS login Keychain required by ad-hoc
direct distribution. It deliberately omits Team-ID-dependent Keychain Sharing:
an empty access group passes `codesign` but launchd rejects an ad-hoc App. App
startup exercises secure storage, so CI catches `errSecMissingEntitlement`.
For existing VMs, helper protocol 4 copies the current bridge installer into the
guest and creates a managed SSH loopback forward when the old Lima template has
no static port 32512 mapping.

v1.0.11 fixes PC/SC protocol negotiation for T=0-only SIMs. The native bridge
tries explicit T=0 first, falls back to explicit T=1 for other cards, and reuses
the selected protocol for every reset. It never asks Apple PC/SC to negotiate
`ANY`, which returned `SCARD_W_UNRESPONSIVE_CARD` for a verified working T=0 card.

`tools/configure-apple-release-signing.sh` remains available for an optional
future Developer ID signed and notarized distribution.

The VM forwards only HTTPS management port 8443 and the bounded WebRTC WSS range
8089-8139 to the LAN. It never exposes the Docker daemon or socket.
