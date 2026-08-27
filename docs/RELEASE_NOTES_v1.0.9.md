# MDD Sim Gateway Native Apps v1.0.9

此版本实现 Mac USB PC/SC 读卡器到 Linux VM 的原生桥接。

- `mdd-hostd` 使用 macOS 系统 PC/SC framework 发现第一个已插卡的物理读卡器，并转发
  ATR、供电/复位控制和 APDU；不会记录 APDU、IMSI、ICCID 或密钥内容。
- 桥接使用 vsmartcard 官方 VPCD 两字节大端长度帧协议；Lima 的 32512 端口仅绑定
  `127.0.0.1`，不会暴露到局域网。
- Linux guest 从校验过的 vsmartcard 0.8 源码构建独立单槽 `libifdvpcd`，与 modem
  多槽驱动使用不同共享对象，避免状态别名、重复读卡器和幽灵卡槽。
- host-service protocol 升级到 3。覆盖安装后 App 启动即替换旧 helper；如果 VM 已运行，
  helper 会自动执行轻量 `macos-pcsc` reconcile，不重装网关、不删除 VM。
- 新增 ARM64 macOS PCSC framework 链接检查、VPCD 帧单测、隐私静态检查和一次性
  Ubuntu 24.04 guest 驱动真实构建/`ldd` 检查。
- 当前自动桥接一个已插卡的 Mac PC/SC 读卡器；热拔插后会自动重连。

---

This release implements the native bridge from a Mac USB PC/SC reader into the Linux VM.

- `mdd-hostd` discovers the first physical reader with an inserted card through the macOS PC/SC
  framework and relays ATR, power/reset control, and APDUs. APDU bodies and subscriber or key
  material are never logged.
- The bridge uses vsmartcard's official two-byte big-endian VPCD framing. Lima port 32512 is
  bound to `127.0.0.1` only and is never exposed to the LAN.
- The Linux guest builds a separate one-slot `libifdvpcd` from verified vsmartcard 0.8 source.
  It cannot alias modem multi-slot state or create duplicate reader devices.
- Host-service protocol 3 replaces the legacy helper on App launch. If the VM is already
  running, a lightweight `macos-pcsc` reconcile configures the bridge without reinstalling the
  gateway or deleting the VM.
- CI verifies ARM64 macOS PCSC framework linkage, VPCD frames and privacy properties, and builds
  and checks the actual guest driver in a disposable Ubuntu 24.04 container.
- One inserted Mac PC/SC reader is bridged automatically; hot-unplug/replug reconnects.
