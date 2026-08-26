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
the LAN. It does not expose Docker's socket or daemon TCP port. Hardware access
will use a separately authenticated host bridge because Apple Virtualization
does not offer general USB passthrough equivalent to a Linux host.
