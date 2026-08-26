import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({required this.state, super.key});
  final GatewayState state;
  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final Map<String, JsonMap> _results = {};
  String? _lineId;
  String _logs = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _lineId = widget.state.instances.firstOrNull?['id']?.toString();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              Tab(text: '健康检查'),
              Tab(text: '宿主机'),
              Tab(text: '实时日志'),
              Tab(text: '支持包'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_health(), _host(), _logsPage(), _bundle()],
          ),
        ),
      ],
    );
  }

  Widget _health() => ListView(
    padding: const EdgeInsets.all(22),
    children: widget.state.devices.isEmpty
        ? [
            const SectionCard(
              child: EmptyState(
                icon: Icons.health_and_safety_outlined,
                title: '没有设备',
                message: '连接设备后可执行端到端健康检查。',
              ),
            ),
          ]
        : [
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (
                      var index = 0;
                      index < widget.state.devices.length;
                      index++
                    )
                      SizedBox(
                        width: wide
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth,
                        child: _HealthCard(
                          device: widget.state.devices[index],
                          result:
                              _results[widget.state.devices[index]['id']
                                  ?.toString()],
                          onRun: () =>
                              _runDiagnostics(widget.state.devices[index]),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
  );

  Widget _host() {
    final host = widget.state.system['host'] is Map
        ? Map<String, dynamic>.from(widget.state.system['host'] as Map)
        : <String, dynamic>{};
    final alerts = widget.state.system['host_alerts'] is List
        ? widget.state.system['host_alerts'] as List
        : const [];
    final memory = host['memory'] is Map ? host['memory'] as Map : const {};
    final disk = host['disk'] is Map ? host['disk'] as Map : const {};
    final network = host['network'] is Map ? host['network'] as Map : const {};
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        if (alerts.isNotEmpty)
          SectionCard(
            title: '需要处理',
            trailing: TextButton(
              onPressed: _clearAlerts,
              child: const Text('清除告警'),
            ),
            child: Column(
              children: [
                for (final alert in alerts.whereType<Map>())
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (alert['severity'] == 'critical'
                          ? Theme.of(context).colorScheme.errorContainer
                          : Theme.of(context).colorScheme.tertiaryContainer),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${alert['code']}${alert['detail'] == null ? '' : ' · ${alert['detail']}'}',
                    ),
                  ),
              ],
            ),
          ),
        if (alerts.isNotEmpty) const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final width = wide
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: SectionCard(
                    title: '机器',
                    child: Column(
                      children: [
                        _HostFact(label: '型号', value: host['model']),
                        _HostFact(label: '运行时间', value: host['uptime_seconds']),
                        _HostFact(
                          label: '温度',
                          value: host['temperature_c'] == null
                              ? null
                              : '${host['temperature_c']} °C',
                        ),
                        _HostFact(
                          label: 'CPU',
                          value: host['cpu_mhz'] == null
                              ? null
                              : '${host['cpu_mhz']} MHz',
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: SectionCard(
                    title: '内存与存储',
                    child: Column(
                      children: [
                        _HostFact(
                          label: '内存使用',
                          value: memory['used_percent'] == null
                              ? null
                              : '${memory['used_percent']}% / ${memory['total_mb']} MB',
                        ),
                        _HostFact(
                          label: 'Swap',
                          value: memory['swap_used_mb'] == null
                              ? null
                              : '${memory['swap_used_mb']} / ${memory['swap_total_mb']} MB',
                        ),
                        _HostFact(
                          label: '磁盘使用',
                          value: disk['used_percent'] == null
                              ? null
                              : '${disk['used_percent']}% · ${disk['free_mb']} MB 可用',
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: SectionCard(
                    title: '网络',
                    child: Column(
                      children: [
                        _HostFact(
                          label: '默认接口',
                          value: (network['default_interfaces'] as List?)?.join(
                            ', ',
                          ),
                        ),
                        _HostFact(label: '接口错误', value: network['counters']),
                        _HostFact(
                          label: 'USB 上联',
                          value: network['usb_attached'],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: SectionCard(
                    title: 'USB 设备',
                    child:
                        (host['usb_devices'] is List &&
                            (host['usb_devices'] as List).isNotEmpty)
                        ? Column(
                            children: [
                              for (final device in host['usb_devices'] as List)
                                _HostFact(label: 'USB', value: device),
                            ],
                          )
                        : const Text('没有宿主机 USB 清单。'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _logsPage() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      SectionCard(
        title: '线路实时日志',
        subtitle: '只读取有界尾部，不把完整运行目录复制到客户端。',
        trailing: OutlinedButton.icon(
          onPressed: _lineId == null || _busy ? null : _loadLogs,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('读取'),
        ),
        child: Column(
          children: [
            LinePicker(
              lines: widget.state.instances,
              value: _lineId,
              onChanged: (value) => setState(() => _lineId = value),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 360),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                _logs.isEmpty ? '选择线路并读取最近 300 行日志。' : _logs,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _bundle() {
    final repo = Uri.tryParse(
      widget.state.system['repository_url']?.toString() ??
          'https://github.com/MddIdd/mdd-sim-gateway',
    );
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        SectionCard(
          title: '脱敏支持包',
          subtitle: '包含状态、配置结构和有限日志；会移除已知的 SIM 标识、号码、PIN、Token、URL、激活码和密钥。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.tertiaryContainer.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.privacy_tip_outlined),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('自动脱敏不能代替人工检查。分享前请解压并确认其中没有真实身份、凭据或短信正文。'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _saveBundle,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('生成并保存支持包'),
                  ),
                  OutlinedButton.icon(
                    onPressed: repo == null
                        ? null
                        : () => launchUrl(repo.resolve('/issues/new/choose')),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('提交 GitHub Issue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _runDiagnostics(JsonMap device) async {
    final id = device['id'].toString();
    try {
      final result = await widget.state.api.deviceDiagnostics(id);
      if (mounted) setState(() => _results[id] = result);
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _clearAlerts() async {
    await widget.state.api.clearHostAlerts();
    await widget.state.refresh();
  }

  Future<void> _loadLogs() async {
    final id = _lineId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.state.api.logs(id);
      if (mounted) {
        setState(
          () => _logs =
              (result['logs'] ?? result['output'] ?? result['raw'] ?? result)
                  .toString(),
        );
      }
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveBundle() async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.state.api.supportBundle();
      final location = await getSaveLocation(
        suggestedName:
            'mdd-support-${DateTime.now().toIso8601String().replaceAll(':', '-')}.tar.gz',
      );
      if (location != null) {
        await XFile.fromData(
          bytes,
          mimeType: 'application/gzip',
          name: 'mdd-support.tar.gz',
        ).saveTo(location.path);
      }
      if (mounted && location != null) _toast('支持包已保存。分享前请人工复核脱敏内容。');
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.device,
    required this.result,
    required this.onRun,
  });
  final JsonMap device;
  final JsonMap? result;
  final VoidCallback onRun;
  @override
  Widget build(BuildContext context) {
    final checks = result?['checks'] is List
        ? result!['checks'] as List
        : const [];
    return SectionCard(
      title: (device['name'] ?? device['model'] ?? device['id']).toString(),
      trailing: OutlinedButton.icon(
        onPressed: onRun,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('运行诊断'),
      ),
      child: checks.isEmpty
          ? const Text('尚未运行诊断。')
          : Column(
              children: [
                for (final check in checks.whereType<Map>())
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      check['ok'] == true
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      color: check['ok'] == true
                          ? const Color(0xFF18A66A)
                          : Theme.of(context).colorScheme.error,
                    ),
                    title: Text((check['name'] ?? '检查').toString()),
                    subtitle: Text((check['detail'] ?? '').toString()),
                  ),
              ],
            ),
    );
  }
}

class _HostFact extends StatelessWidget {
  const _HostFact({required this.label, required this.value});
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Flexible(
          child: Text(
            displayValue(value),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
