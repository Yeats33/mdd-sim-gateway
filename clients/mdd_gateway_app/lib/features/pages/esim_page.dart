import 'package:flutter/material.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class EsimPage extends StatefulWidget {
  const EsimPage({required this.state, super.key});

  final GatewayState state;

  @override
  State<EsimPage> createState() => _EsimPageState();
}

class _EsimPageState extends State<EsimPage> {
  String? _reader;
  JsonMap _status = {};
  JsonMap _chip = {};
  List<JsonMap> _profiles = [];
  List<JsonMap> _notifications = [];
  bool _loading = false;

  List<String> get _readers => widget.state.cards
      .map((card) => (card['reader'] ?? card['name'])?.toString())
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  @override
  void initState() {
    super.initState();
    _reader = _readers.firstOrNull;
    _load();
  }

  @override
  void didUpdateWidget(covariant EsimPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_reader == null && _readers.isNotEmpty) {
      _reader = _readers.first;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        SectionCard(
          title: 'eUICC 读卡器',
          subtitle: '双安全元件卡会按 Profile 返回的 SE/AID 精确操作。',
          trailing: IconButton.filledTonal(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _readers.contains(_reader) ? _reader : null,
                  decoration: const InputDecoration(
                    labelText: '读卡器',
                    prefixIcon: Icon(Icons.credit_card_rounded),
                  ),
                  items: [
                    for (final reader in _readers)
                      DropdownMenuItem(
                        value: reader,
                        child: Text(reader, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _reader = value);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _reader == null ? null : _download,
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载 Profile'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loading) const LinearProgressIndicator(),
        if (_reader == null)
          const SectionCard(
            child: EmptyState(
              icon: Icons.sim_card_alert_outlined,
              title: '未发现 eUICC 读卡器',
              message: '插入受支持的 PC/SC eUICC 卡后重新扫描。',
            ),
          )
        else ...[
          _ChipCard(status: _status, chip: _chip),
          const SizedBox(height: 14),
          SectionCard(
            title: 'eSIM Profiles',
            subtitle: '启停、重命名和删除操作都作用于当前选定读卡器。',
            child: _profiles.isEmpty
                ? const EmptyState(
                    icon: Icons.sim_card_download_outlined,
                    title: '没有 Profile',
                    message: '输入运营商激活码或使用 SM-DS 发现服务下载。',
                  )
                : Column(
                    children: [
                      for (final profile in _profiles)
                        _ProfileTile(
                          profile: profile,
                          onEnable: () => _enable(profile),
                          onDisable: () => _disable(profile),
                          onRename: () => _rename(profile),
                          onDelete: () => _delete(profile),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: '运营商通知',
            subtitle: '通知来自 eUICC；处理后仍需按需要显式移除。',
            trailing: OutlinedButton.icon(
              onPressed: _discover,
              icon: const Icon(Icons.travel_explore_rounded),
              label: const Text('SM-DS 发现'),
            ),
            child: _notifications.isEmpty
                ? const Text('没有待处理通知。')
                : Column(
                    children: [
                      for (final notification in _notifications)
                        ListTile(
                          leading: const Icon(
                            Icons.notifications_active_outlined,
                          ),
                          title: Text(
                            (notification['type'] ??
                                    notification['event'] ??
                                    'eSIM 通知')
                                .toString(),
                          ),
                          subtitle: Text(
                            (notification['address'] ??
                                    notification['detail'] ??
                                    '')
                                .toString(),
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                onPressed: () =>
                                    _processNotification(notification),
                                tooltip: '处理',
                                icon: const Icon(Icons.done_all_rounded),
                              ),
                              IconButton(
                                onPressed: () =>
                                    _removeNotification(notification),
                                tooltip: '移除',
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Future<void> _load() async {
    final reader = _reader;
    setState(() => _loading = true);
    try {
      final status = await widget.state.api.esimStatus();
      if (reader == null) {
        if (mounted) setState(() => _status = status);
        return;
      }
      final results = await Future.wait([
        widget.state.api.esimChip(reader),
        widget.state.api.esimProfiles(reader),
        widget.state.api.esimNotifications(reader),
      ]);
      if (!mounted || reader != _reader) return;
      setState(() {
        _status = status;
        _chip = results[0];
        _profiles = _list(results[1], 'profiles');
        _notifications = _list(results[2], 'notifications');
      });
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final reader = _reader;
    if (reader == null) return;
    final activation = TextEditingController();
    final confirmation = TextEditingController();
    final result = await showDialog<JsonMap>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载 eSIM Profile'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: activation,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'LPA 激活码',
                  hintText: r'LPA:1$…',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmation,
                obscureText: true,
                decoration: const InputDecoration(labelText: '确认码（如运营商要求）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'activation_code': activation.text.trim(),
              'confirmation_code': confirmation.text,
              'reader': reader,
            }),
            child: const Text('开始下载'),
          ),
        ],
      ),
    );
    activation.dispose();
    confirmation.dispose();
    if (result == null || (result['activation_code'] as String).isEmpty) return;
    try {
      await widget.state.mutate((api) => api.esimDownload(result));
      await _load();
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  JsonMap _target(JsonMap profile) => {
    if (profile['se_id'] != null) 'se_id': profile['se_id'],
    if (profile['aid'] != null) 'aid': profile['aid'],
  };

  Future<void> _enable(JsonMap profile) async {
    final reader = _reader;
    final iccid = profile['iccid']?.toString();
    if (reader == null || iccid == null) return;
    if (!await confirmAction(
      context,
      title: '启用这个 Profile？',
      message: '当前启用的 Profile 可能会先停用，相关线路将重新连接。',
    )) {
      return;
    }
    await widget.state.mutate(
      (api) => api.esimEnable(iccid, reader, _target(profile)),
    );
    await _load();
  }

  Future<void> _disable(JsonMap profile) async {
    final reader = _reader;
    final iccid = profile['iccid']?.toString();
    if (reader == null || iccid == null) return;
    if (!await confirmAction(
      context,
      title: '停用这个 Profile？',
      message: '使用该 Profile 的 4G、VoWiFi、来电和短信都会中断。',
    )) {
      return;
    }
    await widget.state.mutate(
      (api) => api.esimDisable(iccid, reader, _target(profile)),
    );
    await _load();
  }

  Future<void> _rename(JsonMap profile) async {
    final reader = _reader;
    final iccid = profile['iccid']?.toString();
    if (reader == null || iccid == null) return;
    final controller = TextEditingController(
      text: (profile['nickname'] ?? '').toString(),
    );
    final nickname = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile 名称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nickname == null) return;
    await widget.state.mutate(
      (api) => api.esimNickname(iccid, nickname, reader, _target(profile)),
    );
    await _load();
  }

  Future<void> _delete(JsonMap profile) async {
    final reader = _reader;
    final iccid = profile['iccid']?.toString();
    if (reader == null || iccid == null) return;
    if (!await confirmAction(
      context,
      title: '永久删除 eSIM Profile？',
      message: '将从当前 eUICC 删除 $iccid。除非运营商允许重新下载，否则无法恢复。',
      dangerous: true,
      confirmLabel: '永久删除',
    )) {
      return;
    }
    await widget.state.mutate(
      (api) => api.esimDelete(iccid, reader, _target(profile)),
    );
    await _load();
  }

  Future<void> _discover() async {
    final reader = _reader;
    if (reader == null) return;
    try {
      await widget.state.mutate((api) => api.esimDiscovery({'reader': reader}));
      await _load();
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _processNotification(JsonMap notification) async {
    final reader = _reader;
    if (reader == null) return;
    await widget.state.mutate(
      (api) =>
          api.esimProcessNotifications(reader, sequence: notification['seq']),
    );
    await _load();
  }

  Future<void> _removeNotification(JsonMap notification) async {
    final reader = _reader;
    final sequence = notification['seq'];
    if (reader == null || sequence == null) return;
    if (!await confirmAction(
      context,
      title: '移除这条 eSIM 通知？',
      message: '只从 eUICC 通知队列中移除序号 $sequence。',
    )) {
      return;
    }
    await widget.state.mutate(
      (api) =>
          api.esimRemoveNotification(sequence, reader, _target(notification)),
    );
    await _load();
  }

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

class _ChipCard extends StatelessWidget {
  const _ChipCard({required this.status, required this.chip});

  final JsonMap status;
  final JsonMap chip;

  @override
  Widget build(BuildContext context) {
    final info = chip['chip'] is Map ? chip['chip'] as Map : chip;
    return SectionCard(
      title: 'eUICC 信息',
      trailing: StatusPill(
        status['available'] == false ? 'lpac 不可用' : '可用',
        kind: status['available'] == false
            ? StatusKind.danger
            : StatusKind.success,
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 14,
        children: [
          _ChipFact(label: 'EID', value: info['eid']),
          _ChipFact(
            label: '固件',
            value: info['firmware'] ?? info['euicc_firmware_version'],
          ),
          _ChipFact(label: '安全元件', value: info['se_count'] ?? info['se_id']),
          _ChipFact(
            label: '剩余空间',
            value: info['free_space'] ?? info['free_nvram'],
          ),
        ],
      ),
    );
  }
}

class _ChipFact extends StatelessWidget {
  const _ChipFact({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
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
        SelectableText(
          displayValue(value),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.onEnable,
    required this.onDisable,
    required this.onRename,
    required this.onDelete,
  });

  final JsonMap profile;
  final VoidCallback onEnable;
  final VoidCallback onDisable;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final enabled =
        profile['enabled'] == true ||
        profile['state']?.toString().toLowerCase() == 'enabled';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: const Icon(Icons.sim_card_rounded),
      ),
      title: Text(
        (profile['nickname'] ??
                profile['service_provider_name'] ??
                profile['name'] ??
                'eSIM Profile')
            .toString(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${profile['iccid'] ?? '—'}${profile['se_id'] == null ? '' : ' · SE ${profile['se_id']}'}',
      ),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 3,
        children: [
          StatusPill(
            enabled ? '已启用' : '已停用',
            kind: enabled ? StatusKind.success : StatusKind.neutral,
          ),
          IconButton(
            onPressed: enabled ? onDisable : onEnable,
            tooltip: enabled ? '停用' : '启用',
            icon: Icon(
              enabled
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') onRename();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}
