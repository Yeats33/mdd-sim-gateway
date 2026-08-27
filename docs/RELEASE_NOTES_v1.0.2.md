# MDD Sim Gateway Native Apps v1.0.2

此版本针对 macOS 27 上仍会触发的 WebRTC Library Validation 启动崩溃进行兼容修复。

- 主 App 的 Hardened Runtime 签名现在包含 Apple 官方
  `com.apple.security.cs.disable-library-validation` 例外，允许加载内嵌 WebRTC Framework。
- CI 仍会从内到外 ad-hoc 重签所有嵌套 Mach-O、Framework、Bundle 和辅助程序，并拒绝
  遗留的第三方 Team ID。
- 启动测试改为通过 LaunchServices 的 `open -n -W` 启动，使 App 由 `launchd` 托管，匹配
  用户从 Finder 打开的实际路径；进程必须保持运行至少 5 秒。
- Android APK 继续使用原有 RSA-4096 发布密钥签名，仅包含 `arm64-v8a`。
- IPA 仍为未签名归档，需要越狱设备或由用户自己的 Apple 身份二次签名。

禁用 Library Validation 会降低针对动态库注入的部分 Hardened Runtime 防护。这是 Apple
为需要加载第三方 Framework 的 App 提供的明确运行时例外；本版本仍保留其他 Hardened
Runtime 保护。

---

This release addresses the WebRTC Library Validation launch failure that still occurs on macOS 27.

- The host app's Hardened Runtime signature now includes Apple's documented
  `com.apple.security.cs.disable-library-validation` exception so it can load the bundled WebRTC
  framework.
- CI continues to ad-hoc sign all nested Mach-O files, frameworks, bundles, and helpers from the
  inside out, and rejects any remaining third-party Team ID.
- The launch test now uses LaunchServices via `open -n -W`, which parents the app through `launchd`
  like a Finder launch, and requires it to remain alive for at least five seconds.
- The Android APK remains signed by the existing RSA-4096 key and contains only `arm64-v8a`.
- The IPA remains unsigned and requires a jailbroken device or re-signing with the user's own
  Apple identity.

Disabling Library Validation reduces part of Hardened Runtime's protection against dynamic-library
injection. This is Apple's explicit runtime exception for apps that must load third-party
frameworks; the other Hardened Runtime protections remain enabled.
