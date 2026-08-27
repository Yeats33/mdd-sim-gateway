# MDD Sim Gateway Native Apps v1.0.6

此版本修复 Apple Silicon Linux VM 启动时找不到 Lima guest agent 的问题。

- App 现在保留 Lima 官方的 `<prefix>/bin` 与 `<prefix>/share/lima` 目录结构。
- DMG 内置与 `limactl` 配套的 `lima-guestagent.Linux-aarch64.gz`，不依赖用户另行安装
  `lima-additional-guestagents`。
- macOS CI 会验证 guest agent 文件位置、gzip 完整性和 Linux ELF 文件头，然后继续验证
  单文件 VM 模板、helper 健康检查与 LaunchServices 启动。
- v1.0.5 使用的 `Resources/limactl` 入口会作为内部兼容链接保留；已由旧版本创建的
  `mdd-sim-gateway` VM 和仍在运行的 helper 可以继续使用，不要求删除现有实例。
- Android 仍为 arm64-v8a 签名 APK；iOS 为 unsigned IPA；macOS 为 ad-hoc signed
  Apple Silicon DMG。

---

This release fixes Apple Silicon Linux VM startup failing because Lima could not locate its guest
agent.

- The App now preserves Lima's upstream `<prefix>/bin` and `<prefix>/share/lima` layout.
- The DMG bundles the matching `lima-guestagent.Linux-aarch64.gz`; users do not need to install
  `lima-additional-guestagents` separately.
- macOS CI validates the guest agent location, gzip integrity, and Linux ELF header before
  validating the single-file VM template, helper health, and LaunchServices startup.
- The v1.0.5 `Resources/limactl` entry point remains as an internal compatibility link. Existing
  `mdd-sim-gateway` VMs and still-running helpers remain reusable; no deletion is required.
- Android remains a signed arm64-v8a APK, iOS an unsigned IPA, and macOS an ad-hoc signed Apple
  Silicon DMG.
