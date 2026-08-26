import 'package:flutter/material.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class EgressPage extends StatefulWidget {
  const EgressPage({required this.state, super.key});

  final GatewayState state;

  @override
  State<EgressPage> createState() => _EgressPageState();
}

class _EgressPageState extends State<EgressPage> {
  JsonMap _settings = {};
  JsonMap _live = {};
  bool _loading = false;
  bool _reveal = false;

  JsonMap get _proxy => _settings['proxy'] is Map
      ? Map<String, dynamic>.from(_settings['proxy'] as Map)
      : <String, dynamic>{
          'enabled': false,
          'profiles': <String, dynamic>{},
          'exits': <String, dynamic>{},
        };

  JsonMap get _profiles => _proxy['profiles'] is Map
      ? Map<String, dynamic>.from(_proxy['profiles'] as Map)
      : {};
  JsonMap get _exits => _proxy['exits'] is Map
      ? Map<String, dynamic>.from(_proxy['exits'] as Map)
      : {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final proxy = _proxy;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        SectionCard(
          title: '国家代理出口',
          subtitle: '出口失败时只停止对应 SIM 的 VoWiFi，不回落到错误国家或宿主机默认出口。',
          trailing: Switch(
            value: proxy['enabled'] == true,
            onChanged: (value) => _patchProxy({'enabled': value}),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  proxy['enabled'] == true
                      ? '已启用按 SIM 国家隔离出口。所有非直连路径都会验证 UDP 500/4500。'
                      : '当前绕过国家出口；已保存的代理和国家绑定不会删除。',
                ),
              ),
              StatusPill(
                proxy['enabled'] == true ? '已启用' : '已停用',
                kind: proxy['enabled'] == true
                    ? StatusKind.success
                    : StatusKind.neutral,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '代理库',
          subtitle: '订阅、单节点和 SOCKS5 可以被多个国家出口复用。',
          trailing: Wrap(
            spacing: 6,
            children: [
              IconButton(
                onPressed: () => setState(() => _reveal = !_reveal),
                tooltip: _reveal ? '隐藏敏感信息' : '显示敏感信息',
                icon: Icon(
                  _reveal
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _addProfile,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加代理'),
              ),
            ],
          ),
          child: _profiles.isEmpty
              ? const EmptyState(
                  icon: Icons.vpn_key_off_outlined,
                  title: '没有代理',
                  message: '添加订阅、单节点或支持 UDP ASSOCIATE 的 SOCKS5。',
                )
              : Column(
                  children: [
                    for (final entry in _profiles.entries)
                      _ProxyTile(
                        id: entry.key,
                        profile: Map<String, dynamic>.from(entry.value as Map),
                        reveal: _reveal,
                        usedBy: _exits.entries
                            .where(
                              (exit) =>
                                  (exit.value as Map?)?['profile_id'] ==
                                  entry.key,
                            )
                            .map((exit) => exit.key.toUpperCase())
                            .toList(),
                        onEdit: () => _editProfile(entry.key),
                        onTest: () => _testProfile(entry.key),
                        onDelete: () => _removeProfile(entry.key),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '国家出口',
          subtitle: '每个国家选择一个代理，并可为订阅锁定或优选具体节点。',
          trailing: FilledButton.tonalIcon(
            onPressed: _addExit,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('添加国家'),
          ),
          child: _exits.isEmpty
              ? const EmptyState(
                  icon: Icons.route_outlined,
                  title: '没有国家出口',
                  message: '添加 SIM 所属国家，再选择代理来源。',
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final entry in _exits.entries)
                          SizedBox(
                            width: wide
                                ? (constraints.maxWidth - 12) / 2
                                : constraints.maxWidth,
                            child: _ExitCard(
                              country: entry.key,
                              exit: Map<String, dynamic>.from(
                                entry.value as Map,
                              ),
                              live: _liveExit(entry.key),
                              profiles: _profiles,
                              onChanged: (patch) =>
                                  _patchExit(entry.key, patch),
                              onTest: () => _testExit(entry.key),
                              onDelete: () => _removeExit(entry.key),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : _advanced,
              icon: const Icon(Icons.data_object_rounded),
              label: const Text('高级 JSON'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('保存并应用'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.state.api.settings(),
        widget.state.api.egressStatus(),
      ]);
      if (mounted) {
        setState(() {
          _settings = results[0];
          _live = results[1];
        });
      }
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _patchProxy(JsonMap patch) {
    setState(
      () => _settings = {
        ..._settings,
        'proxy': {..._proxy, ...patch},
      },
    );
  }

  void _patchExit(String country, JsonMap patch) {
    _patchProxy({
      'exits': {
        ..._exits,
        country: {
          ...Map<String, dynamic>.from(_exits[country] as Map? ?? {}),
          ...patch,
        },
      },
    });
  }

  JsonMap _liveExit(String country) {
    final liveExits = _live['exits'];
    final value = liveExits is Map ? liveExits[country] : null;
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await widget.state.api.saveSettings(_settings);
      await widget.state.api.refreshEgress();
      await _load();
      if (mounted) _toast('国家出口已保存并应用。');
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addProfile() async {
    final profile = await _profileDialog();
    if (profile == null) return;
    final id =
        'proxy-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    _patchProxy({
      'profiles': {..._profiles, id: profile},
    });
  }

  Future<void> _editProfile(String id) async {
    final current = Map<String, dynamic>.from(_profiles[id] as Map);
    final profile = await _profileDialog(current: current);
    if (profile != null) {
      _patchProxy({
        'profiles': {..._profiles, id: profile},
      });
    }
  }

  Future<JsonMap?> _profileDialog({JsonMap? current}) async {
    final type = ValueNotifier<String>(
      (current?['type'] ?? 'subscription').toString(),
    );
    final name = TextEditingController(text: current?['name']?.toString());
    final primary = TextEditingController(
      text: (current?['url'] ?? current?['value'] ?? current?['server'] ?? '')
          .toString(),
    );
    final port = TextEditingController(
      text: (current?['port'] ?? 1080).toString(),
    );
    final username = TextEditingController(
      text: current?['username']?.toString(),
    );
    final password = TextEditingController(
      text: current?['password']?.toString(),
    );
    final result = await showDialog<JsonMap>(
      context: context,
      builder: (context) => ValueListenableBuilder(
        valueListenable: type,
        builder: (context, selected, _) => AlertDialog(
          title: Text(current == null ? '添加代理' : '编辑代理'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: const [
                    DropdownMenuItem(
                      value: 'subscription',
                      child: Text('订阅链接'),
                    ),
                    DropdownMenuItem(value: 'node', child: Text('单独节点')),
                    DropdownMenuItem(value: 'socks5', child: Text('SOCKS5')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      type.value = value;
                      primary.clear();
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: primary,
                  obscureText: !_reveal,
                  maxLines: selected == 'node' ? 3 : 1,
                  decoration: InputDecoration(
                    labelText: selected == 'subscription'
                        ? '订阅 URL'
                        : selected == 'node'
                        ? '节点分享链接'
                        : '服务器',
                  ),
                ),
                if (selected == 'socks5') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: port,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '端口'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: username,
                          decoration: const InputDecoration(
                            labelText: '用户名（可选）',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: password,
                    obscureText: !_reveal,
                    decoration: const InputDecoration(labelText: '密码（可选）'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final selectedType = type.value;
                final value = <String, dynamic>{
                  'type': selectedType,
                  'name': name.text.trim().isEmpty
                      ? 'New proxy'
                      : name.text.trim(),
                };
                if (selectedType == 'subscription') {
                  value.addAll({
                    'url': primary.text.trim(),
                    'refresh_minutes': current?['refresh_minutes'] ?? 30,
                  });
                }
                if (selectedType == 'node') {
                  value['value'] = primary.text.trim();
                }
                if (selectedType == 'socks5') {
                  value.addAll({
                    'server': primary.text.trim(),
                    'port': int.tryParse(port.text) ?? 1080,
                    'username': username.text,
                    'password': password.text,
                  });
                }
                Navigator.pop(context, value);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    type.dispose();
    name.dispose();
    primary.dispose();
    port.dispose();
    username.dispose();
    password.dispose();
    return result;
  }

  Future<void> _testProfile(String id) async {
    try {
      final result = await widget.state.api.testProxyProfile(
        id,
        Map<String, dynamic>.from(_profiles[id] as Map),
      );
      if (mounted) _toast('UDP 测试通过：${result['latency_ms'] ?? '—'} ms');
    } on Object catch (error) {
      if (mounted) _toast('UDP 测试失败：$error');
    }
  }

  void _removeProfile(String id) {
    final used = _exits.entries
        .where((entry) => (entry.value as Map?)?['profile_id'] == id)
        .map((entry) => entry.key.toUpperCase())
        .toList();
    if (used.isNotEmpty) {
      _toast('这个代理正在被 ${used.join(', ')} 使用。');
      return;
    }
    final profiles = {..._profiles}..remove(id);
    _patchProxy({'profiles': profiles});
  }

  Future<void> _addExit() async {
    final controller = TextEditingController();
    final country = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加国家出口'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          maxLength: 2,
          decoration: const InputDecoration(
            labelText: 'ISO 两字母国家代码',
            hintText: 'CN / JP / US',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim().toLowerCase()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (country == null || country.length != 2 || _exits.containsKey(country)) {
      return;
    }
    _patchExit(country, {
      'enabled': true,
      'profile_id': '',
      'keywords': [country.toUpperCase()],
    });
  }

  Future<void> _testExit(String country) async {
    try {
      final result = await widget.state.api.testEgress(country);
      if (mounted) {
        _toast(
          '出口 ${country.toUpperCase()} UDP 测试通过：${result['latency_ms'] ?? '—'} ms',
        );
      }
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
    await _load();
  }

  void _removeExit(String country) {
    final exits = {..._exits}..remove(country);
    _patchProxy({'exits': exits});
  }

  Future<void> _advanced() async {
    final edited = await showJsonEditor(
      context,
      title: '高级出口设置',
      value: _proxy,
    );
    if (edited != null) _patchProxy(edited);
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _ProxyTile extends StatelessWidget {
  const _ProxyTile({
    required this.id,
    required this.profile,
    required this.reveal,
    required this.usedBy,
    required this.onEdit,
    required this.onTest,
    required this.onDelete,
  });
  final String id;
  final JsonMap profile;
  final bool reveal;
  final List<String> usedBy;
  final VoidCallback onEdit;
  final VoidCallback onTest;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final type = profile['type']?.toString() ?? 'subscription';
    final sensitive =
        (profile['url'] ?? profile['value'] ?? profile['server'] ?? '')
            .toString();
    final display = reveal
        ? sensitive
        : (sensitive.isEmpty ? '—' : '••••••••••••');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Icon(
          type == 'subscription'
              ? Icons.rss_feed_rounded
              : type == 'node'
              ? Icons.link_rounded
              : Icons.dns_outlined,
        ),
      ),
      title: Text(
        (profile['name'] ?? id).toString(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '$type · $display${usedBy.isEmpty ? ' · 未分配' : ' · ${usedBy.join(', ')}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            onPressed: onTest,
            tooltip: '测试 UDP',
            icon: const Icon(Icons.speed_rounded),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: '移除',
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _ExitCard extends StatelessWidget {
  const _ExitCard({
    required this.country,
    required this.exit,
    required this.live,
    required this.profiles,
    required this.onChanged,
    required this.onTest,
    required this.onDelete,
  });
  final String country;
  final JsonMap exit;
  final JsonMap live;
  final JsonMap profiles;
  final ValueChanged<JsonMap> onChanged;
  final VoidCallback onTest;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final ready = live['ready'] == true;
    final selected = exit['profile_id']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  country.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              StatusPill(
                ready ? 'UDP 已验证' : '未连接',
                kind: ready ? StatusKind.success : StatusKind.warning,
              ),
              Switch(
                value: exit['enabled'] != false,
                onChanged: (value) => onChanged({'enabled': value}),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: profiles.containsKey(selected) ? selected : null,
            decoration: const InputDecoration(labelText: '出口代理'),
            items: [
              for (final entry in profiles.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    ((entry.value as Map)['name'] ?? entry.key).toString(),
                  ),
                ),
            ],
            onChanged: (value) => onChanged({'profile_id': value ?? ''}),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: (exit['keywords'] as List?)?.join(', ') ?? '',
            decoration: const InputDecoration(labelText: '节点名称关键词（逗号分隔）'),
            onFieldSubmitted: (value) => onChanged({
              'keywords': value
                  .split(',')
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList(),
            }),
          ),
          if (live['node'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '当前节点：${live['node']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (live['error'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                live['error'].toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onTest,
                icon: const Icon(Icons.speed_rounded),
                label: const Text('测试 UDP'),
              ),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('移除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
