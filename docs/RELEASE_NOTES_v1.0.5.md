# MDD Sim Gateway Native Apps v1.0.5

此版本修复 v1.0.4 在创建 VM 时将字面量 `__MDD_BASE__` 当成文件路径的问题。

- DMG 构建现在对完整 `mdd-vm.yaml` 执行 `limactl template copy --embed-all`，App 内只包含
  一个最终、自包含的 VM 模板。
- 构建会拒绝仍含 `__MDD_BASE__` 或 Ubuntu 运行时模板定位器的产物，避免同类问题进入
  Release。
- `mdd-hostd` 运行时只替换本机 gateway source 挂载路径，不再拼接基础模板路径。
- macOS CI 使用 App 自带的 `limactl` 验证最终渲染模板，然后启动 helper、检查
  `/v1/health` 并通过 LaunchServices 启动 App。
- Android 仍为随机生成密钥对应证书签名的 arm64-v8a APK；iOS 为 unsigned IPA；macOS
  为 ad-hoc signed Apple Silicon DMG。

---

This release fixes v1.0.4 treating the literal `__MDD_BASE__` placeholder as a VM-template
filename during VM creation.

- The DMG build now runs `limactl template copy --embed-all` over the complete `mdd-vm.yaml`,
  leaving one final, self-contained VM template in the App bundle.
- The build rejects output that still contains `__MDD_BASE__` or an Ubuntu runtime template
  locator, preventing the same failure from reaching a Release.
- `mdd-hostd` now replaces only the machine-specific gateway source mount at runtime; it no
  longer constructs a base-template path.
- macOS CI validates the final rendered template with the App's bundled `limactl`, starts the
  helper, checks `/v1/health`, and launches the App through LaunchServices.
- Android remains a certificate-signed arm64-v8a APK, iOS an unsigned IPA, and macOS an ad-hoc
  signed Apple Silicon DMG.
