# MDD Sim Gateway Native Apps v1.0.10

此版本修复 macOS `PlatformException` / Security `-34018`，并自动兼容旧 VM 的 PC/SC
bridge 转发。

- Debug 与 Release App entitlement 均加入 Flutter Secure Storage 要求的空
  `keychain-access-groups`；最终 ad-hoc 签名会重新提取并强制核对该 entitlement。
- 直接分发版本使用 macOS 登录 Keychain，而不是需要 Team ID 的 Data Protection
  Keychain；session cookie 仍由系统 Keychain 加密并受 ACL 保护。
- App 每次启动都会做一次无副作用 Keychain 查询，因此 LaunchServices CI 会在打包阶段
  捕获 `errSecMissingEntitlement`，不再等到登录或“检测 SIM”后才暴露。
- host-service protocol 升级到 4。helper 使用 `limactl copy` 把当前 installer 复制进旧
  VM，绕过旧 source mount；如果旧 Lima 实例没有 32512 forward，会使用实例自己的
  `ssh.config` 创建受管的 loopback-only SSH tunnel。
- SIM 尚未识别时，设备卡会显示 guest 返回的具体 PC/SC/APDU 错误，而不再统一显示
  “插入可读 SIM”。

---

This release fixes macOS Security error `-34018` and makes the PC/SC bridge automatic for reused
VMs.

- Debug and Release entitlements now include the empty `keychain-access-groups` capability
  required by Flutter Secure Storage, and the final ad-hoc signature is audited for it.
- Direct distribution uses the macOS login Keychain rather than the Team-ID-dependent Data
  Protection Keychain. Session cookies remain encrypted and ACL-protected by the OS.
- Every App launch performs a harmless Keychain lookup, allowing LaunchServices CI to catch
  `errSecMissingEntitlement` during packaging.
- Host-service protocol 4 copies the current installer into an old VM with `limactl copy`. If the
  reused Lima instance lacks static port 32512 forwarding, its own `ssh.config` drives a managed,
  loopback-only SSH tunnel.
- An unreadable SIM now displays its specific guest PC/SC/APDU error instead of a generic prompt.
