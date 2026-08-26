import 'package:flutter/material.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({required this.state, super.key});

  final GatewayState state;

  @override
  Widget build(BuildContext context) {
    final onlineCellular = state.devices
        .where((device) => _capState(device, 'cellular') == 'on')
        .length;
    final onlineVowifi = state.devices
        .where((device) => _capState(device, 'vowifi') == 'on')
        .length;
    final attention = state.devices.where((device) {
      final values = [
        _capState(device, 'cellular'),
        _capState(device, 'vowifi'),
      ];
      return values.any((value) => value == 'error' || value == 'degraded');
    }).length;
    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const _ResponsibleUseNotice(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 960
                  ? 4
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    width: width,
                    label: '设备',
                    value: state.devices.length,
                    icon: Icons.hub_outlined,
                  ),
                  _MetricCard(
                    width: width,
                    label: '4G 在线',
                    value: onlineCellular,
                    icon: Icons.signal_cellular_alt_rounded,
                    color: const Color(0xFF18A66A),
                  ),
                  _MetricCard(
                    width: width,
                    label: 'VoWiFi 在线',
                    value: onlineVowifi,
                    icon: Icons.wifi_calling_3_rounded,
                    color: const Color(0xFF4E83FF),
                  ),
                  _MetricCard(
                    width: width,
                    label: '需要处理',
                    value: attention,
                    icon: Icons.error_outline_rounded,
                    color: attention > 0 ? const Color(0xFFE3565A) : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (state.devices.isEmpty)
            const SectionCard(
              child: EmptyState(
                icon: Icons.usb_off_rounded,
                title: '尚未发现设备',
                message: 'Mac 网关会在 Linux VM 启动后自动发现读卡器和蜂窝模块。',
              ),
            )
          else
            SectionCard(
              title: '线路概览',
              subtitle: '显示后端报告的实际状态；开关请求不会伪装成已经生效。',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (var index = 0; index < state.devices.length; index++)
                        SizedBox(
                          width: wide
                              ? (constraints.maxWidth - 14) / 2
                              : constraints.maxWidth,
                          child: _DeviceSummary(
                            device: state.devices[index],
                            index: index,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          _HostSummary(system: state.system, update: state.update),
        ],
      ),
    );
  }

  static String _capState(JsonMap device, String key) {
    final capabilities = device['capabilities'];
    final capability = capabilities is Map ? capabilities[key] : device[key];
    final raw = capability is Map
        ? capability['actual'] ?? capability['state'] ?? capability['enabled']
        : capability;
    final normalized = raw?.toString().toLowerCase() ?? 'off';
    if ([
      'ok',
      'working',
      'registered',
      'connected',
      'active',
      'true',
    ].contains(normalized)) {
      return 'on';
    }
    return normalized;
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final double width;
  final String label;
  final int value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '$value',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceSummary extends StatelessWidget {
  const _DeviceSummary({required this.device, required this.index});

  final JsonMap device;
  final int index;

  @override
  Widget build(BuildContext context) {
    final name =
        (device['name'] ??
                device['label'] ??
                device['model'] ??
                '设备 ${index + 1}')
            .toString();
    final sim = device['sim'] is Map ? device['sim'] as Map : const {};
    final status = device['status'] is Map ? device['status'] as Map : const {};
    final state =
        status['state'] ??
        status['label'] ??
        (device['present'] == false ? '离线' : '已连接');
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                device['device_type'] == 'reader'
                    ? Icons.credit_card_rounded
                    : Icons.router_rounded,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              StatusPill(state.toString(), kind: statusKind(state)),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            (sim['name'] ?? sim['carrier'] ?? device['carrier'] ?? 'SIM')
                .toString(),
          ),
          const SizedBox(height: 4),
          Text(
            (sim['number'] ?? device['number'] ?? device['reader'] ?? '等待线路信息')
                .toString(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CapabilityMini(
                  label: '4G',
                  value: _cap(device, 'cellular'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CapabilityMini(
                  label: 'VoWiFi',
                  value: _cap(device, 'vowifi'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Object? _cap(JsonMap value, String name) {
    final caps = value['capabilities'];
    final cap = caps is Map ? caps[name] : null;
    return cap is Map ? cap['actual'] ?? cap['state'] : cap;
  }
}

class _CapabilityMini extends StatelessWidget {
  const _CapabilityMini({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final kind = statusKind(value);
    final color = switch (kind) {
      StatusKind.success => const Color(0xFF18A66A),
      StatusKind.warning => const Color(0xFFF29C38),
      StatusKind.danger => const Color(0xFFE3565A),
      StatusKind.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          Text(
            displayValue(value),
            style: TextStyle(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _HostSummary extends StatelessWidget {
  const _HostSummary({required this.system, required this.update});

  final JsonMap system;
  final JsonMap update;

  @override
  Widget build(BuildContext context) {
    final alerts = system['host_alerts'] is List
        ? system['host_alerts'] as List
        : const [];
    return SectionCard(
      title: 'Mac 网关与 Linux VM',
      subtitle: '宿主状态来自网关控制面；VM 和 Docker 细节由 Mac Rust 服务补充。',
      trailing: StatusPill(
        alerts.isEmpty ? '运行正常' : '${alerts.length} 条告警',
        kind: alerts.isEmpty ? StatusKind.success : StatusKind.warning,
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 16,
        children: [
          _Fact(label: '版本', value: system['version'] ?? '—'),
          _Fact(
            label: '运行时间',
            value: system['uptime'] ?? system['uptime_seconds'] ?? '—',
          ),
          _Fact(
            label: '最新版本',
            value: update['latest'] ?? system['version'] ?? '—',
          ),
          _Fact(label: '自动更新', value: system['auto_update'] ?? false),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
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
          const SizedBox(height: 5),
          Text(
            displayValue(value),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ResponsibleUseNotice extends StatelessWidget {
  const _ResponsibleUseNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 20),
          SizedBox(width: 11),
          Expanded(child: Text('仅供号码实名持有人在运营商允许范围内自用；禁止群呼、营销骚扰和向第三人提供线路。')),
        ],
      ),
    );
  }
}
