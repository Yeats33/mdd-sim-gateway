# MDD Sim Gateway Native Apps v1.0.8

此版本修复 Linux VM 已启动、但网关控制面从未安装而只等待超时的问题。

- `not_installed`、`stopped` 和 `running but not ready` 三种可恢复状态现在都会执行幂等
  网关安装/修复，不再把“启动 VM”误当成“安装网关”。
- `mdd-hostd install` 检测 VM 已运行时不会重复执行 `limactl start`，而会直接进入 guest
  执行安装。
- App 与 helper 使用 host-service protocol 2。覆盖升级时会识别并安全终止只监听本机
  48630 的旧 MDD helper，再启动当前版本，避免继续使用旧行为。
- gateway source 按原生 App 版本分期，确保 v1.0.8 不会复用旧版本的 `install.sh`。
- 控制面超时等待延长到 120 秒，并附带最多 200 行的有限日志快照；不会再调用永不返回
  的 follow 日志。
- 保留 v1.0.7 的 Lima VZ entitlement、guest agent、单文件模板和真实 VZ 初始化检查。

---

This release fixes the App starting an existing Linux VM but never installing its missing gateway
control plane.

- Every recoverable `not_installed`, `stopped`, or `running but not ready` state now performs an
  idempotent gateway install/repair instead of mistaking VM startup for gateway installation.
- `mdd-hostd install` skips a duplicate `limactl start` when the VM is already running and enters
  the guest installer directly.
- App and helper negotiate host-service protocol 2. An in-place upgrade identifies and safely
  terminates the legacy MDD listener bound only to local port 48630 before launching the current
  helper.
- Bundled gateway source is staged by native App version, so v1.0.8 cannot reuse an older
  `install.sh`.
- Readiness waits for up to 120 seconds and returns a bounded 200-line log snapshot on timeout;
  it no longer invokes a never-ending follow operation.
- Lima VZ entitlements, guest agent, self-contained template, and VZ initialization checks from
  v1.0.7 remain enforced.
