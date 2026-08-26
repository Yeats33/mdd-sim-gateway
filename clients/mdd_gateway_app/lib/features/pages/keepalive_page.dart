import 'package:flutter/material.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class KeepalivePage extends StatefulWidget {
  const KeepalivePage({required this.state, super.key});

  final GatewayState state;

  @override
  State<KeepalivePage> createState() => _KeepalivePageState();
}

class _KeepalivePageState extends State<KeepalivePage> {
  List<JsonMap> _lines = [];
  String? _expanded;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final present = _lines.where((line) => line['in_gateway'] == true).toList();
    final absent = _lines.where((line) => line['in_gateway'] != true).toList();
    final keepingOk = present.where((line) {
      final keep = line['keepalive'] is Map
          ? line['keepalive'] as Map
          : const {};
      return keep['enabled'] == true &&
          !['failed', 'balance_low'].contains(keep['last_status']);
    }).length;
    final attention = present.length - keepingOk;
    final expiring = _lines.where((line) {
      final days = num.tryParse(line['days_to_expiry']?.toString() ?? '');
      return days != null && days <= 7;
    }).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 760
                  ? (constraints.maxWidth - 36) / 4
                  : (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _KeepMetric(
                    width: width,
                    label: '在网关中',
                    value: present.length,
                  ),
                  _KeepMetric(
                    width: width,
                    label: '保号正常',
                    value: keepingOk,
                    color: const Color(0xFF18A66A),
                  ),
                  _KeepMetric(
                    width: width,
                    label: '需要处理',
                    value: attention,
                    color: const Color(0xFFF29C38),
                  ),
                  _KeepMetric(
                    width: width,
                    label: '7 天内到期',
                    value: expiring,
                    color: expiring > 0 ? const Color(0xFFE3565A) : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (_loading) const LinearProgressIndicator(),
          if (_lines.isEmpty && !_loading)
            const SectionCard(
              child: EmptyState(
                icon: Icons.schedule_outlined,
                title: '还没有线路',
                message: '添加 SIM 线路后，可在此维护余额、套餐有效期和保号计划。',
              ),
            )
          else
            SectionCard(
              title: '余额与号码保活',
              subtitle: '付费保号动作必须逐线路启用；“立即运行”不会在未确认时发送真实短信。',
              child: Column(
                children: [
                  for (final line in present)
                    _LinePanel(
                      line: line,
                      expanded: _expanded == line['instance']?.toString(),
                      onToggle: () => setState(
                        () => _expanded =
                            _expanded == line['instance']?.toString()
                            ? null
                            : line['instance']?.toString(),
                      ),
                      onAllowance: () => _editAllowance(line),
                      onQueryRule: () => _editQueryRule(line),
                      onQuery: () => _queryAllowance(line),
                      onKeepalive: () => _editKeepalive(line),
                      onRun: () => _runNow(line),
                    ),
                ],
              ),
            ),
          if (absent.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: '当前不在网关中（${absent.length}）',
              subtitle: '这些 SIM 无法执行保号，但到期信息仍然保留。',
              child: Column(
                children: [
                  for (final line in absent)
                    ListTile(
                      leading: const Icon(Icons.sim_card_alert_outlined),
                      title: Text(
                        (line['name'] ?? line['instance']).toString(),
                      ),
                      subtitle: Text(
                        '${line['msisdn'] ?? '号码未知'} · 到期 ${_allowance(line)['valid_until'] ?? '未知'}',
                      ),
                      trailing: IconButton(
                        onPressed: () => _deleteAbsent(line),
                        tooltip: '删除旧线路',
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.tertiaryContainer.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.payments_outlined),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '预付费号码通常需要真实、可计费的使用行为才能保号。余额查询通常不能替代付费使用；任何测试短信也可能产生运营商费用。',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await widget.state.api.keepaliveSummary();
      if (mounted) setState(() => _lines = _list(result, 'lines'));
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editAllowance(JsonMap line) async {
    final id = line['instance'].toString();
    final result = await widget.state.api.allowance(id);
    if (!mounted) return;
    final current = result['allowance'] is Map
        ? Map<String, dynamic>.from(result['allowance'] as Map)
        : <String, dynamic>{};
    final edited = await showJsonEditor(
      context,
      title: '余额与套餐信息',
      value: current,
      description: '可维护余额、短信/流量/语音余量、激活日期和有效期。',
    );
    if (edited == null) return;
    await widget.state.mutate((api) => api.saveAllowance(id, edited));
    await _load();
  }

  Future<void> _editQueryRule(JsonMap line) async {
    final id = line['instance'].toString();
    final result = await widget.state.api.allowanceQueryRule(id);
    if (!mounted) return;
    final rule = result['rule'] is Map
        ? Map<String, dynamic>.from(result['rule'] as Map)
        : <String, dynamic>{};
    final effective = rule['effective'] is Map
        ? Map<String, dynamic>.from(rule['effective'] as Map)
        : <String, dynamic>{'recipient': '', 'body': ''};
    final edited = await showJsonEditor(
      context,
      title: '余额查询规则',
      value: effective,
      description: '填写运营商余额查询短信的服务号码与准确正文。查询可能产生短信费用。',
    );
    if (edited == null) return;
    await widget.state.mutate((api) => api.saveAllowanceQueryRule(id, edited));
    await _load();
  }

  Future<void> _queryAllowance(JsonMap line) async {
    final id = line['instance'].toString();
    final ruleResult = await widget.state.api.allowanceQueryRule(id);
    final rule = ruleResult['rule'] is Map
        ? ruleResult['rule'] as Map
        : const {};
    final effective = rule['effective'] is Map
        ? rule['effective'] as Map
        : const {};
    if (effective['recipient'] == null || effective['body'] == null) {
      if (mounted) _toast('请先配置这条线路的余额查询规则。');
      return;
    }
    if (!mounted ||
        !await confirmAction(
          context,
          title: '发送余额查询短信？',
          message:
              '将向 ${effective['recipient']} 发送“${effective['body']}”。运营商可能收费，请勿连续重试。',
        )) {
      return;
    }
    final result = await widget.state.api.queryAllowance(id);
    if (mounted) {
      _toast(
        result['ok'] == false ? '提交结果不确定，请先在短信页检查，避免重复计费。' : '查询短信已发送，等待运营商回复。',
      );
    }
    await _load();
  }

  Future<void> _editKeepalive(JsonMap line) async {
    final id = line['instance'].toString();
    final result = await widget.state.api.keepalive(id);
    if (!mounted) return;
    final current = result['keepalive'] is Map
        ? Map<String, dynamic>.from(result['keepalive'] as Map)
        : <String, dynamic>{};
    final edited = await showJsonEditor(
      context,
      title: '保号计划',
      value: current,
      description: 'action=sms 会执行真实可计费短信；action=balance_watch 只监测套餐续费余额。',
    );
    if (edited == null) return;
    await widget.state.mutate((api) => api.saveKeepalive(id, edited));
    await _load();
  }

  Future<void> _runNow(JsonMap line) async {
    final id = line['instance'].toString();
    final keep = line['keepalive'] is Map ? line['keepalive'] as Map : const {};
    final paid = keep['action'] == 'sms';
    final accepted = await confirmAction(
      context,
      title: paid ? '立即发送一条真实计费短信？' : '立即查询余额？',
      message: paid
          ? '这会通过线路 $id 发送真实短信，并按运营商资费计费。只执行一次，不会自动重试。'
          : '这可能向运营商服务号码发送查询短信，并可能产生费用。',
    );
    if (!accepted) return;
    await widget.state.mutate((api) => api.runKeepalive(id));
    await _load();
  }

  Future<void> _deleteAbsent(JsonMap line) async {
    final id = line['instance'].toString();
    if (!await confirmAction(
      context,
      title: '删除不在网关中的线路？',
      message: '将删除线路 $id 的 IMS 设置、PIN 和运行文件，但保留短信与通话历史。仅用于已不再持有的号码。',
      dangerous: true,
      confirmLabel: '删除线路',
    )) {
      return;
    }
    await widget.state.mutate(
      (api) => api.deleteInstance(id, deleteHistory: false),
    );
    await _load();
  }

  static JsonMap _allowance(JsonMap line) => line['allowance'] is Map
      ? Map<String, dynamic>.from(line['allowance'] as Map)
      : {};

  List<JsonMap> _list(JsonMap value, String key) {
    final raw = value[key];
    return raw is List
        ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : [];
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _KeepMetric extends StatelessWidget {
  const _KeepMetric({
    required this.width,
    required this.label,
    required this.value,
    this.color,
  });

  final double width;
  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LinePanel extends StatelessWidget {
  const _LinePanel({
    required this.line,
    required this.expanded,
    required this.onToggle,
    required this.onAllowance,
    required this.onQueryRule,
    required this.onQuery,
    required this.onKeepalive,
    required this.onRun,
  });

  final JsonMap line;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAllowance;
  final VoidCallback onQueryRule;
  final VoidCallback onQuery;
  final VoidCallback onKeepalive;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final keep = line['keepalive'] is Map ? line['keepalive'] as Map : const {};
    final allowance = line['allowance'] is Map
        ? line['allowance'] as Map
        : const {};
    final status = keep['enabled'] != true
        ? '未启用'
        : (keep['last_status'] ?? '已计划').toString();
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: const Icon(Icons.sim_card_rounded)),
          title: Text(
            (line['name'] ?? line['instance']).toString(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${line['msisdn'] ?? '号码未知'} · 余额 ${allowance['balance'] ?? '未知'} · 有效期 ${allowance['valid_until'] ?? '未知'}',
          ),
          trailing: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              StatusPill(status, kind: statusKind(status)),
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
            ],
          ),
          onTap: onToggle,
        ),
        if (expanded)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                OutlinedButton.icon(
                  onPressed: onAllowance,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑余额'),
                ),
                OutlinedButton.icon(
                  onPressed: onQueryRule,
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('查询规则'),
                ),
                OutlinedButton.icon(
                  onPressed: onQuery,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('查询余额'),
                ),
                OutlinedButton.icon(
                  onPressed: onKeepalive,
                  icon: const Icon(Icons.schedule_rounded),
                  label: const Text('保号计划'),
                ),
                FilledButton.icon(
                  onPressed: keep['enabled'] == true ? onRun : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('立即运行一次'),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
