# iOS controller and IPA

The iOS application is a native Flutter controller for a paired Mac or Linux
gateway. It requests only the local-network, camera, and microphone access used
for pairing and VoWiFi calls. ATS allows local networking but the Dart client
still requires HTTPS and explicit SHA-256 certificate confirmation.

The deployment target is iOS 15, matching the supported floor of Flutter 3.44.

An active call may continue audio in the background. Receiving a new call after
iOS suspends or terminates the app requires an APNs/PushKit service and is not
claimed by this LAN-only build; while the app is active, incoming calls use the
gateway's existing WSS softphone path.

## Build the unsigned IPA

On an Apple Silicon Mac with Xcode and Flutter:

```sh
./tools/build-ios-ipa.sh
```

The script compiles with `--no-codesign`, rejects embedded signatures and
provisioning profiles, verifies the bundle identifier, and creates a standard
`Payload/Runner.app` IPA. The resulting IPA requires a jailbroken device or
re-signing with AltStore, Sideloadly, or the user's own Apple identity; it does
not install directly on a stock iPhone.

`tools/configure-apple-release-signing.sh` remains available for an optional
future Apple-signed distribution.
