# MDD Sim Gateway native client

One Flutter codebase provides the macOS control surface and the iOS/Android LAN
controllers. The UI mirrors every operation exposed by `webui/src/api.js` while
the existing gateway remains authoritative.

## Development

```sh
flutter pub get
dart analyze
flutter test
```

Platform packaging lives on the long-lived branches described in
`docs/CLIENT_ARCHITECTURE.md`:

- `platform/macos`: Apple Silicon app plus the Rust VM/Docker supervisor.
- `platform/ios`: local-network, camera, microphone, and IPA configuration.
- `platform/android`: local-network, camera, microphone, and arm64-v8a APK configuration.

## Connection security

The onboarding flow accepts HTTPS only outside loopback development. For the
gateway's installation certificate it shows a SHA-256 fingerprint that must be
compared with the Mac app. The session cookie is stored in Keychain/Keystore and
mutating requests retain the gateway's CSRF requirement.

The softphone uses `sip_ua` and `flutter_webrtc` to match the current JsSIP WSS
path. Incoming and outgoing audio stays between the phone and the selected
gateway line; the client does not expose a reusable external SIP account.
