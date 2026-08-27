# MDD Sim Gateway Native Apps v1.0.3

此版本修复 Mac App 启动本机 Rust 服务时始终超时的问题。

- Flutter 传递的是 `--lima-bin`，而 v1.0.2 中的 `mdd-hostd` CLI 只接受 `--limactl`，
  导致 helper 立即以状态 2 退出。
- `mdd-hostd` 现在以 `--lima-bin` 为正式参数，并保留 `--limactl` 兼容名称。
- CI 会直接启动 DMG 内的 helper，并要求 `/v1/health` 返回正确结果。
- Mac App 现在把 helper stdout/stderr 保存到 Application Support 的 `hostd/hostd.log`，
  并在 helper 提前退出时显示真实状态和日志，而不是统一显示超时。
- 保留 v1.0.2 的 WebRTC Library Validation 兼容修复与 LaunchServices 启动测试。

---

This release fixes the local Rust host service always timing out when launched by the Mac app.

- Flutter passed `--lima-bin`, while the v1.0.2 `mdd-hostd` CLI accepted only `--limactl`,
  causing the helper to exit immediately with status 2.
- `mdd-hostd` now uses `--lima-bin` as the canonical option and retains `--limactl` for
  compatibility.
- CI directly launches the helper bundled in the DMG and requires a valid `/v1/health` response.
- The Mac app persists helper stdout/stderr to `hostd/hostd.log` under Application Support and
  reports the real exit status and log content instead of collapsing all failures into a timeout.
- The WebRTC Library Validation compatibility fix and LaunchServices launch test from v1.0.2
  remain enabled.
