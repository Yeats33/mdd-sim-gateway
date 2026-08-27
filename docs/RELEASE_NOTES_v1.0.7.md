# MDD Sim Gateway Native Apps v1.0.7

此版本修复 VZ 启动时报 `com.apple.security.virtualization` entitlement 缺失的问题。

- `limactl` 现在按 Lima 官方配置单独进行 ad-hoc 重签，保留 network client、network
  server 与 virtualization 三项 entitlement。
- 签名脚本会从最终 App 中重新提取并核对 entitlement，缺少任何一项都会中止构建。
- macOS CI 不再只验证模板：它会在隔离的临时 `LIMA_HOME` 中创建并真正启动 VZ
  Linux-aarch64 最小 VM。支持 VZ 的 Mac 必须完成开机与 guest 架构验证；GitHub 托管
  runner 在 entitlement 与 VZ 初始化通过后，仅允许精确的“硬件未开放 Virtualization”
  原因跳过开机。正式 8 GiB 网关模板仍单独执行完整渲染验证。
- 关闭未使用的 Lima containerd，避免网关安装前额外下载 nerdctl；网关仍由 VM 内的
  Docker 管理。
- Android 仍为 arm64-v8a 签名 APK；iOS 为 unsigned IPA；macOS 为 ad-hoc signed
  Apple Silicon DMG。

---

This release fixes VZ startup failing because the bundled process lacked the
`com.apple.security.virtualization` entitlement.

- `limactl` is now ad-hoc re-signed separately with Lima's official network-client,
  network-server, and virtualization entitlements.
- The signing script extracts and audits the entitlements from the final App, failing the build
  if any required value is absent.
- macOS CI now attempts to create and boot a real VZ Linux-aarch64 VM in an isolated temporary
  `LIMA_HOME`. A VZ-capable Mac must boot and verify the guest architecture; a GitHub-hosted
  runner may skip boot only for the exact hardware-unavailable result after entitlement and VZ
  initialization pass. This 2 GiB smoke is separate from production-template validation.
- Unused Lima containerd is disabled to avoid an extra nerdctl download before the gateway's
  Docker installation.
- Android remains a signed arm64-v8a APK, iOS an unsigned IPA, and macOS an ad-hoc signed Apple
  Silicon DMG.
