# Native client API coverage

This checklist is the acceptance source for parity with `webui/src/api.js`.
Checked items have a Dart client method; screen-level acceptance is tracked by
the feature headings in `CLIENT_ARCHITECTURE.md`.

- [x] Authentication and password endpoints
- [x] Unified devices, hardware, cellular state, capabilities, and diagnostics
- [x] Readers, SIM detection, provisioning, and PIN operations
- [x] Settings, egress, and notification endpoints
- [x] System status, update, backup, maintenance, and support bundle endpoints
- [x] Instances, lifecycle, availability, registration, and logs
- [x] SMS threads, messages, binary messages, sending, and deletion
- [x] Allowance and query-rule endpoints
- [x] Keep-alive configuration, execution, and summary
- [x] Calls, cellular calls, call history, softphone provisioning, and hangup
- [x] Voicemail listing, audio, listened state, and deletion
- [x] eSIM status, chip, profiles, lifecycle, download, discovery, and notifications
- [x] Authenticated live WebSocket feed with reconnect and 4401 handling

The client deliberately does not call `/api/engine/event`; that endpoint is for
authenticated engine-to-control callbacks, not user interfaces.
