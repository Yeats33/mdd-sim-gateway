# Android controller and arm64-v8a APK

The Android branch produces only `arm64-v8a`. The app requests camera access for
pairing, microphone/audio access for VoWiFi calls, and local-network access for
the paired gateway. Cleartext traffic is disabled; a private gateway certificate
is accepted only after the in-app SHA-256 fingerprint confirmation.

## Signed release

The release build never falls back to a debug signing key. Keep the persistent
release private key and certificate backed up outside the repository, then
provide them at build time:

```sh
export MDD_ANDROID_PRIVATE_KEY=/secure/path/android-release-private-key.pk8
export MDD_ANDROID_CERTIFICATE=/secure/path/android-release-certificate.pem
export MDD_ANDROID_KEY_PASSWORD_FILE=/secure/path/android-release-key-password
./tools/build-android-apk.sh
```

The key is an encrypted PKCS#8 DER file used directly by `apksigner`; no Java
KeyStore or key alias is part of the release path. Keep the same private key,
certificate, and password for every future update.

The script builds the split arm64 APK, verifies that no other native ABI is
present, verifies the APK signature, and writes an artifact named
`mdd-sim-gateway-<version>-android-arm64-v8a.apk` under `dist/android/`.
