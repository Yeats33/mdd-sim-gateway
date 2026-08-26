# Native client architecture

The native client suite replaces the browser as the primary user interface while
preserving the gateway's existing Linux and container boundaries. It does not
reimplement IMS, SWu IKE, Asterisk, ModemManager, NetworkManager, sing-box, or
lpac in Dart or Rust.

## Branch ownership

| Branch | Long-lived responsibility |
| --- | --- |
| `main` | Upstream-compatible gateway baseline. |
| `ui/flutter-shared` | Shared Flutter application, API client, state, design system, and feature screens. |
| `platform/macos` | Apple Silicon host application, Rust host daemon, Linux VM, and Docker lifecycle. |
| `platform/ios` | iOS packaging, permissions, local-network pairing, notifications, and call integration. |
| `platform/android` | Android packaging, permissions, local-network pairing, notifications, and arm64-v8a release. |

Shared UI changes land in `ui/flutter-shared` first and are merged into each
platform branch. Platform-specific code does not flow back into the shared
branch unless it is portable.

## Runtime boundary

```text
iOS / Android Flutter client                macOS Flutter client
             |                                      |
             +------- HTTPS + WebSocket ------------+
                                  |
                          Rust host service
                 pairing, discovery, VM and Docker
                                  |
                  Apple Virtualization.framework VM
                                  |
                         Linux + Docker Compose
                  control plane and per-SIM engines
                                  |
                   USB modem / PCSC / eUICC hardware
```

The Rust host service is an adapter and supervisor. The existing Python control
plane remains authoritative for gateway configuration and operations. This keeps
the mature telecom paths intact and makes upstream rebases practical.

## Security model

- Clients accept only HTTPS gateway URLs, except loopback development builds.
- A self-signed installation is trusted through explicit certificate-fingerprint
  confirmation. Trust-on-first-use is never silent.
- The existing session cookie and CSRF token remain supported. The Rust pairing
  service will exchange a one-time QR secret for an app-scoped credential without
  exposing an administrator password to other devices.
- Credentials and session material are stored in Keychain/Keystore through
  Flutter secure storage and are never included in WebDAV snapshots.
- Mobile access is advertised only on the local network. Remote access belongs
  behind a user-configured VPN, not a public listener.

## Complete feature contract

Every platform client exposes the functions applicable to that platform. The
Mac client additionally owns host, VM, and Docker lifecycle.

| Area | Required operations |
| --- | --- |
| Authentication | First-admin setup, login, persistent session, logout, password change. |
| Overview | Live host, device, SIM, cellular, VoWiFi, IMS, balance, and alert state. |
| Devices | Reader discovery, SIM detection, provisioning, PIN verify/change/enable/clear, hardware metadata, capability switches, diagnostics, deletion. |
| Lines | Start, stop, reprovision, country binding, registration, availability, logs, and safe deletion with optional history retention. |
| Messages | Threads, conversation history, binary/SIM-addressed messages, transport selection, send, per-message/conversation/all deletion. |
| Calls | WebRTC softphone provisioning, register, outgoing/incoming call, answer/reject/hang up, mute, DTMF, cellular call fallback, history, voicemail playback and deletion. |
| eSIM | Reader and secure-element selection, EID/chip data, profiles, download/cancel, discovery, enable, disable, rename, delete, notification processing and removal. |
| Balance | Current allowance, plan dates, query rules, manual query, cellular/VoWiFi/automatic transport. |
| Number keeping | Per-line schedule, real paid-SMS warning, balance-watch mode, manual run, result history and summary. |
| Egress | Proxy library, subscriptions/nodes/SOCKS5, country bindings, refresh, per-profile and per-country UDP tests. |
| Notifications | Webhook, Telegram, PushPlus, event switches, privacy controls, test delivery, delivery history and clearing. |
| System | Settings, update check/apply/cancel/progress, backup create/delete, restart/reboot/shutdown, repository metadata. |
| Diagnostics | Host alerts, system status, support bundle, per-device diagnostics, per-line logs, alert clearing. |

Destructive actions always require an explicit confirmation describing the exact
scope. A mobile action must not make an unrelated SIM the implicit target.

## Compatibility strategy

The Dart API client mirrors `webui/src/api.js`. A compatibility path may derive
read-only device cards from instances and cards only when `/api/devices` returns
404, matching the current WebUI behavior. Transient failures must not activate
compatibility mode.
