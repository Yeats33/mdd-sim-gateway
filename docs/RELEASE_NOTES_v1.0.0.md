# MDD Sim Gateway Native Apps v1.0.0

首个原生应用版本：Apple Silicon Mac 使用 Flutter UI、Rust 宿主服务和 Linux/Docker
通信引擎；iOS 与 Android 手机可在局域网内配对并操作网关。

- 完整覆盖设备、SIM/eSIM、4G、飞行模式、VoWiFi、短信、软电话、语音留言、余额保号、
  国家出口、通知、备份、更新和诊断。
- 首次配对核对 HTTPS SHA-256 指纹；软电话 WSS 必须提供同一证书。
- Android APK 仅包含 `arm64-v8a`，使用本项目独立长期发布证书签名。
- IPA 使用 Apple Distribution 和匹配的 Provisioning Profile 签名。
- DMG 使用 Developer ID 签名、Hardened Runtime、公证并附加公证票据。

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
- The IPA is signed with Apple Distribution and its matching provisioning profile.
- The DMG is Developer ID signed, hardened, notarized, and stapled.

Configure the administrator only on a trusted LAN. Use the gateway solely for lines you own and
where permitted by carrier terms and local law. Physical Mac hardware support still depends on
the actual reader, modem, and USB bridge path.
