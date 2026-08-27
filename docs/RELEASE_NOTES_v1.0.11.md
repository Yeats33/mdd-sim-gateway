# MDD Sim Gateway Native Apps v1.0.11

此版本修复 macOS 已读取 ATR、但 MDD bridge 报“未插卡”的 T=0 协议协商问题。

- 实机矩阵确认同一读卡器/卡在 SYSTEM 与 USER scope 下均为：`ANY` 返回
  `SCARD_W_UNRESPONSIVE_CARD (0x80100066)`，显式 T=0 成功，T=1 返回协议不匹配。
- `mdd-hostd` 不再使用 `Protocols::ANY`。它按 T=0、T=1 顺序逐个尝试，支持当前 T=0
  SIM，也保留对真正 T=1 卡的兼容。
- VPCD power/reset 后继续使用首次成功的协议，避免复位时重新触发错误协商。
- 单个 reader 的协议错误不再阻止继续检查其他 reader；日志会保留完整底层 PC/SC
  error chain，但不会记录 ATR、APDU、IMSI、ICCID 或密钥。
- host-service protocol 升级到 5，覆盖安装后自动替换 v1.0.10 helper，无需重建 VM。

---

This release fixes a T=0 negotiation failure where macOS could read the ATR but the MDD bridge
reported that no card was inserted.

- A hardware matrix confirmed that both SYSTEM and USER scopes return
  `SCARD_W_UNRESPONSIVE_CARD (0x80100066)` for `ANY`, succeed with explicit T=0, and reject T=1.
- `mdd-hostd` no longer uses `Protocols::ANY`. It tries explicit T=0 followed by explicit T=1,
  preserving compatibility with genuine T=1 cards.
- VPCD power/reset reuses the initially successful protocol instead of renegotiating.
- A protocol failure from one reader no longer prevents checking later readers. Logs preserve
  the full PC/SC error chain without recording ATR, APDU, IMSI, ICCID, or key material.
- Host-service protocol 5 replaces the v1.0.10 helper automatically; the VM is retained.
