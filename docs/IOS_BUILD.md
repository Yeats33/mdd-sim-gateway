# iOS controller and IPA

The iOS application is a native Flutter controller for a paired Mac or Linux
gateway. It requests only the local-network, camera, and microphone access used
for pairing and VoWiFi calls. ATS allows local networking but the Dart client
still requires HTTPS and explicit SHA-256 certificate confirmation.

An active call may continue audio in the background. Receiving a new call after
iOS suspends or terminates the app requires an APNs/PushKit service and is not
claimed by this LAN-only build; while the app is active, incoming calls use the
gateway's existing WSS softphone path.

## Build an IPA

An installable IPA cannot be produced without the owner's Apple Developer
identity and provisioning profile. On a signing Mac:

```sh
MDD_IOS_EXPORT_OPTIONS_PLIST=/secure/path/ExportOptions.plist \
  ./tools/build-ios-ipa.sh
```

The export options file and signing credentials must remain outside the
repository. TestFlight, Ad Hoc, and Development distribution can use the same
script with the corresponding Xcode export method.
