# Android controller and arm64-v8a APK

The Android branch produces only `arm64-v8a`. The app requests camera access for
pairing, microphone/audio access for VoWiFi calls, and local-network access for
the paired gateway. Cleartext traffic is disabled; a private gateway certificate
is accepted only after the in-app SHA-256 fingerprint confirmation.

## Signed release

The release build never falls back to a debug signing key. Keep the persistent
release keystore backed up outside the repository, then provide it at build time:

```sh
export MDD_ANDROID_KEYSTORE=/secure/path/mdd-release.jks
export MDD_ANDROID_STORE_PASSWORD='...'
export MDD_ANDROID_KEY_ALIAS='mdd'
export MDD_ANDROID_KEY_PASSWORD='...'
./tools/build-android-apk.sh
```

The script builds the split arm64 APK, verifies that no other native ABI is
present, verifies the APK signature, and writes an artifact named
`mdd-sim-gateway-<version>-android-arm64-v8a.apk` under `dist/android/`.
