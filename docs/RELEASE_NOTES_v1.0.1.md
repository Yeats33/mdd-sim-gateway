# MDD Sim Gateway Native Apps v1.0.1

此补丁版本修复 v1.0.0 macOS App 在启动时因 `WebRTC.framework` 与主程序 Team ID
不一致而触发的 `dyld` 崩溃。

- macOS 打包现在按从内到外的顺序显式 ad-hoc 重签所有 Mach-O、Framework、Bundle
  和辅助程序，最后签主 App。
- CI 会拒绝任何仍带第三方 Team ID 的嵌套代码。
- DMG 创建前会在 Apple Silicon runner 上真实启动 App，并要求进程至少保持运行 5 秒。
- Android APK 继续使用原有 RSA-4096 发布密钥签名，仅包含 `arm64-v8a`。
- IPA 仍为未签名归档，需要越狱设备或由用户自己的 Apple 身份二次签名。

DMG 仍是 ad-hoc 签名且未经过 Apple 公证，macOS 首次打开时可能要求在“隐私与安全性”
中明确批准。

---

This patch fixes the v1.0.0 macOS launch crash caused by a Team ID mismatch between
the ad-hoc signed host app and the vendor-signed `WebRTC.framework`.

- The macOS package now explicitly ad-hoc signs every Mach-O, framework, bundle, and
  helper from the deepest nested code outward, then signs the host app last.
- CI rejects any nested code that retains a third-party Team ID.
- Before creating the DMG, CI launches the app on an Apple Silicon runner and requires
  the process to remain alive for at least five seconds.
- The Android APK remains signed by the existing RSA-4096 release key and contains only
  `arm64-v8a`.
- The IPA remains unsigned and requires a jailbroken device or re-signing with the user's
  own Apple identity.

The DMG remains ad-hoc signed and is not notarized by Apple, so macOS may require explicit
approval in Privacy & Security on first launch.
