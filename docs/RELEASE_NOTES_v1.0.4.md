# MDD Sim Gateway Native Apps v1.0.4

此版本修复 Lima v2 无法解析/找到 Ubuntu 24.04 VM 基础模板的问题，并清理可控 CI warning。

- 构建 DMG 时使用 `limactl template copy --embed-all template:ubuntu-24.04` 生成自包含
  `mdd-base.yaml`，不再依赖用户机器上的 Homebrew Lima 模板目录。
- `mdd-hostd` 将自包含基础模板的绝对路径写入最终 VM 配置。
- macOS-only CI 会使用 bundle 内的 `limactl template validate` 验证最终渲染模板，随后再
  启动 helper 并检查 `/v1/health`。
- Artifact actions 已升级到 Node 24：upload-artifact v7.0.1、download-artifact v8.0.1。
- macOS Release 固定为 arm64，并明确 Flutter Assemble 每次执行，消除跨架构 native asset
  和 Xcode build phase warning。
- runner 中未使用且未受信任的 `aws/tap` 会在安装 Lima 前被精确移除；不会关闭 Homebrew
  的 tap 安全检查。

---

This release fixes Lima v2 failing to resolve or locate the Ubuntu 24.04 VM base template and
removes controllable CI warnings.

- The DMG build generates a self-contained `mdd-base.yaml` with
  `limactl template copy --embed-all template:ubuntu-24.04`, avoiding any dependency on a
  Homebrew Lima template directory on the user's Mac.
- `mdd-hostd` writes the absolute bundled base-template path into the rendered VM configuration.
- macOS-only CI validates the final rendered template with the bundled `limactl`, then launches
  the helper and checks `/v1/health`.
- Artifact actions now use Node 24: upload-artifact v7.0.1 and download-artifact v8.0.1.
- The macOS Release is arm64-only and marks Flutter Assemble as intentionally always-run,
  removing cross-architecture native-asset and Xcode build-phase warnings.
- The unused untrusted `aws/tap` on the runner is removed precisely before installing Lima;
  Homebrew's tap security checks remain enabled.
