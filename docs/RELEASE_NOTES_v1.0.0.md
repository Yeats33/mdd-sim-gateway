# MDD Sim Gateway Native Apps v1.0.0

首个原生应用版本：Apple Silicon Mac 使用 Flutter UI、Rust 宿主服务和 Linux/Docker
通信引擎；iOS 与 Android 手机可在局域网内配对并操作网关。

- 完整覆盖设备、SIM/eSIM、4G、飞行模式、VoWiFi、短信、软电话、语音留言、余额保号、
  国家出口、通知、备份、更新和诊断。
- 首次配对核对 HTTPS SHA-256 指纹；软电话 WSS 必须提供同一证书。
- Android APK 仅包含 `arm64-v8a`，使用本项目独立长期发布证书签名。
- IPA 未签名，供越狱设备使用，或由 AltStore、Sideloadly、开发者自己的 Apple 身份二次签名；
  它不能直接安装到普通未越狱 iPhone。
- DMG 内的 App 使用 ad-hoc 签名，未经过 Apple 公证；首次打开时 macOS Gatekeeper 可能要求
  用户在“隐私与安全性”中明确批准。

首次连接真实读卡器或蜂窝模块前，请在可信局域网中完成管理员设置，并遵守号码实名、
运营商协议和当地法律。Mac 物理硬件兼容性仍取决于实际读卡器、模块和 USB 桥接路径。

---

The first native-app release combines a Flutter control surface, a Rust macOS host supervisor,
and the existing Linux/Docker telecom engine. iOS and Android clients pair with and operate the
gateway over the local network.

- Full UI coverage for devices, SIM/eSIM, 4G, flight mode, VoWiFi, SMS, softphone calls,
  voicemail, allowance and number keeping, country egress, notifications, backup, updates,
  and diagnostics.
- Pairing confirms the HTTPS SHA-256 fingerprint, and softphone WSS must present the same cert.
- The Android APK contains only `arm64-v8a` and uses this project's dedicated long-term key.
- The IPA is unsigned. It is intended for jailbroken devices or re-signing with AltStore,
  Sideloadly, or the user's own Apple identity; it cannot be installed directly on a stock iPhone.
- The app inside the DMG is ad-hoc signed and is not notarized by Apple. Gatekeeper may require
  explicit approval in Privacy & Security on first launch.

Configure the administrator only on a trusted LAN. Use the gateway solely for lines you own and
where permitted by carrier terms and local law. Physical Mac hardware support still depends on
the actual reader, modem, and USB bridge path.
