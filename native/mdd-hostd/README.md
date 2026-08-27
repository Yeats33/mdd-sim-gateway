# mdd-hostd

`mdd-hostd` is the small native boundary between the Flutter macOS app and the
Linux gateway. It does not implement telecom protocols. It supervises an
Apple-Virtualization-backed Lima VM and invokes the existing installer inside
that VM, where Docker, systemd, ModemManager, NetworkManager, Asterisk, SWu IKE,
sing-box, and lpac retain their current responsibilities.

The service listens on `127.0.0.1:48630`. Except for `/v1/health`, requests need
the bearer token stored with mode `0600` in the application-support directory.
Arguments are passed directly to `limactl`; user-controlled values are never
interpolated into a shell command.

Development:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```

The template forwards the management port and bounded WebRTC WSS port range to
the LAN. It does not expose Docker's socket or daemon TCP port. Apple
Virtualization does not offer general USB passthrough equivalent to a Linux
host. On macOS, `mdd-hostd` therefore reads one inserted physical card via the
system PC/SC framework and relays VPCD frames through a loopback-only Lima
forward to an isolated one-slot virtual reader in the guest. The bridge port is
never exposed to the LAN.
