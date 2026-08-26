import 'package:flutter/material.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({required this.state, super.key});

  final GatewayState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${state.devices.length} 台设备 · ${state.cards.length} 张可见卡',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _detect(context),
              icon: const Icon(Icons.search_rounded),
              label: const Text('检测 SIM'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (state.devices.isEmpty)
          SectionCard(
            child: EmptyState(
              icon: Icons.usb_rounded,
              title: '等待硬件',
              message: '插入 PC/SC 读卡器或受支持的蜂窝模块后，网关会自动创建设备记录。',
              action: FilledButton.icon(
                onPressed: state.refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新扫描'),
              ),
            ),
          )
        else
          for (var index = 0; index < state.devices.length; index++) ...[
            _DeviceCard(
              state: state,
              device: state.devices[index],
              index: index,
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  Future<void> _detect(BuildContext context) async {
    try {
      final result = await state.mutate((api) => api.detect());
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('SIM 检测结果'),
          content: SelectableText(result.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.state,
    required this.device,
    required this.index,
  });

  final GatewayState state;
  final JsonMap device;
  final int index;

  @override
  Widget build(BuildContext context) {
    final name = (device['name'] ?? device['model'] ?? '设备 ${index + 1}')
        .toString();
    final present = device['present'] != false;
    final sim = device['sim'] is Map ? device['sim'] as Map : const {};
    return SectionCard(
      title: name,
      subtitle:
          [
                device['device_type'] == 'reader' ? '智能卡读卡器' : '蜂窝模块',
                device['stable_path'] ?? device['reader'],
              ]
              .where((value) => value != null && value.toString().isNotEmpty)
              .join(' · '),
      trailing: StatusPill(
        present ? '已连接' : '离线',
        kind: present ? StatusKind.success : StatusKind.neutral,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Detail(
                  label: 'SIM',
                  value: sim['name'] ?? sim['carrier'] ?? '未识别',
                ),
              ),
              Expanded(
                child: _Detail(
                  label: '号码',
                  value: sim['number'] ?? device['number'] ?? '—',
                ),
              ),
              Expanded(
                child: _Detail(
                  label: '运营商',
                  value: sim['operator'] ?? device['operator'] ?? '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CapabilitySwitch(
            state: state,
            device: device,
            keyName: 'cellular',
            label: '4G 网络',
            icon: Icons.signal_cellular_alt_rounded,
          ),
          const Divider(height: 24),
          _CapabilitySwitch(
            state: state,
            device: device,
            keyName: 'flight',
            label: '飞行模式',
            icon: Icons.flight_rounded,
          ),
          const Divider(height: 24),
          _CapabilitySwitch(
            state: state,
            device: device,
            keyName: 'vowifi',
            label: 'VoWiFi / Wi-Fi Calling',
            icon: Icons.wifi_calling_3_rounded,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _diagnostics(context),
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('设备诊断'),
              ),
              OutlinedButton.icon(
                onPressed: () => _hardware(context),
                icon: const Icon(Icons.memory_rounded),
                label: const Text('硬件信息'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pinActions(context),
                icon: const Icon(Icons.pin_outlined),
                label: const Text('PIN 管理'),
              ),
              OutlinedButton.icon(
                onPressed: () => _lineActions(context),
                icon: const Icon(Icons.tune_rounded),
                label: const Text('线路操作'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _diagnostics(BuildContext context) async {
    try {
      final result = await state.mutate(
        (api) => api.deviceDiagnostics(device['id'].toString()),
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result['ok'] == true ? '诊断通过' : '诊断发现问题'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SelectableText(result.toString()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _hardware(BuildContext context) async {
    final edited = await showJsonEditor(
      context,
      title: '硬件信息',
      value: {
        if (device['imei'] != null) 'imei': device['imei'],
        if (device['name'] != null) 'name': device['name'],
      },
    );
    if (edited == null) return;
    try {
      await state.mutate(
        (api) => api.saveDeviceHardware(device['id'].toString(), edited),
      );
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _pinActions(BuildContext context) async {
    final lines = state.instances
        .where(
          (line) => line['device_id']?.toString() == device['id']?.toString(),
        )
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'PIN 管理',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('验证 / 修改 / 启停 SIM PIN'),
                subtitle: const Text('选择读卡器并在确认窗口中输入 PIN'),
                onTap: () {
                  Navigator.pop(context);
                  _pinDialog(context);
                },
              ),
              if (lines.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.key_off_outlined),
                  title: const Text('清除已保存的线路 PIN'),
                  subtitle: Text('仅清除网关本地保存值，不更改 SIM 卡 PIN 状态。'),
                  onTap: () async {
                    Navigator.pop(context);
                    final line = lines.first;
                    if (await confirmAction(
                      context,
                      title: '清除线路 PIN？',
                      message:
                          '只删除线路 ${line['name'] ?? line['id']} 在网关本地保存的 PIN，不会更改 SIM 卡。',
                    )) {
                      await state.mutate(
                        (api) => api.clearPin(line['id'].toString()),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pinDialog(BuildContext context) async {
    final pin = TextEditingController();
    final reader = device['reader']?.toString();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('验证 SIM PIN'),
        content: TextField(
          controller: pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, pin.text),
            child: const Text('验证'),
          ),
        ],
      ),
    );
    pin.dispose();
    if (result == null || result.isEmpty) return;
    try {
      await state.mutate((api) => api.verifyPin(result, 0, reader: reader));
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _lineActions(BuildContext context) async {
    final lines = state.instances
        .where(
          (line) =>
              line['device_id']?.toString() == device['id']?.toString() ||
              line['reader'] == device['reader'],
        )
        .toList();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这个设备还没有已配置线路。')));
      return;
    }
    final line = lines.first;
    final id = line['id'].toString();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('启动线路'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await state.mutate((api) => api.startLine(id));
              },
            ),
            ListTile(
              leading: const Icon(Icons.stop_rounded),
              title: const Text('停止线路'),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (await confirmAction(
                  context,
                  title: '停止线路？',
                  message: '线路 $id 将停止 VoWiFi，来电和短信会暂时不可用。',
                )) {
                  await state.mutate((api) => api.stopLine(id));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('重新开通'),
              subtitle: const Text('重新读取 SIM 并重建引擎配置'),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (await confirmAction(
                  context,
                  title: '重新开通线路？',
                  message: 'SIM、ePDG 和 IMS 连接将被重建。',
                )) {
                  await state.mutate((api) => api.reprovision(id));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.app_registration_rounded),
              title: const Text('重新注册 IMS'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await state.mutate((api) => api.registerLine(id));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilitySwitch extends StatelessWidget {
  const _CapabilitySwitch({
    required this.state,
    required this.device,
    required this.keyName,
    required this.label,
    required this.icon,
  });

  final GatewayState state;
  final JsonMap device;
  final String keyName;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final capabilities = device['capabilities'];
    final raw = capabilities is Map ? capabilities[keyName] : null;
    final capability = raw is Map ? raw : const {};
    final desired =
        capability['desired'] == true || capability['enabled'] == true;
    final actual =
        (capability['actual'] ??
                capability['state'] ??
                (desired ? 'starting' : 'off'))
            .toString();
    final unavailable =
        device['present'] == false ||
        capability['available'] == false ||
        actual == 'unsupported';
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                (capability['reason'] ?? '实际状态：$actual').toString(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        StatusPill(actual, kind: statusKind(actual)),
        const SizedBox(width: 8),
        Switch(
          value: desired,
          onChanged: unavailable ? null : (value) => _change(context, value),
        ),
      ],
    );
  }

  Future<void> _change(BuildContext context, bool next) async {
    final field = keyName == 'flight' ? 'flight_mode' : '${keyName}_enabled';
    final impact = keyName == 'cellular'
        ? '更改 4G 会重建 SIM 访问，VoWiFi 可能重连 20–60 秒。'
        : keyName == 'vowifi'
        ? 'VoWiFi 线路、ePDG 和 IMS 状态会随之改变。'
        : '飞行模式会改变蜂窝射频状态，但不会代替独立的 4G 和 VoWiFi 设置。';
    if (!await confirmAction(
      context,
      title: '${next ? '开启' : '关闭'}$label？',
      message: impact,
    )) {
      return;
    }
    try {
      await state.mutate(
        (api) =>
            api.patchDeviceCapabilities(device['id'].toString(), {field: next}),
      );
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            displayValue(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(error.toString())));
}
