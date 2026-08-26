import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class SystemPage extends StatefulWidget {
  const SystemPage({
    required this.state,
    required this.themeMode,
    required this.onThemeChanged,
    super.key,
  });
  final GatewayState state;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  JsonMap _settings = {};
  JsonMap _status = {};
  JsonMap _update = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _load();
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
              Tab(text: '常规'),
              Tab(text: 'Web 访问'),
              Tab(text: '通话与 VoWiFi'),
              Tab(text: '安全'),
              Tab(text: '备份与更新'),
              Tab(text: '维护'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _GeneralSettings(
                value: _settings,
                themeMode: widget.themeMode,
                onTheme: widget.onThemeChanged,
                onChanged: _replace,
              ),
              _WebSettings(value: _settings, onChanged: _replace),
              _VoiceSettings(value: _settings, onChanged: _replace),
              _SecuritySettings(
                value: _settings,
                status: _status,
                onChanged: _replace,
                onPassword: _changePassword,
              ),
              _BackupUpdateSettings(
                settings: _settings,
                status: _status,
                update: _update,
                onChanged: _replace,
                onCreateBackup: _createBackup,
                onDeleteBackup: _deleteBackup,
                onCheckUpdate: _checkUpdate,
                onApplyUpdate: _applyUpdate,
              ),
              _MaintenanceSettings(onAction: _maintenance),
            ],
          ),
        ),
        if (_tabs.index < 4)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('保存设置'),
            ),
          ),
      ],
    );
  }

  void _replace(JsonMap value) => setState(() => _settings = value);
  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.state.api.settings(),
        widget.state.api.systemStatus(),
        widget.state.api.checkUpdate(),
      ]);
      if (mounted) {
        setState(() {
          _settings = results[0];
          _status = results[1];
          _update = results[2];
        });
      }
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await widget.state.api.saveSettings(_settings);
      if (mounted) {
        setState(() => _settings = saved);
        _toast('设置已保存。');
      }
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword(String current, String next) async {
    try {
      await widget.state.api.authPassword(current, next);
      if (mounted) _toast('密码已修改，请重新登录。');
      await widget.state.logout();
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _createBackup() async {
    try {
      await widget.state.api.createBackup();
      await _load();
      if (mounted) _toast('本地备份已创建。');
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _deleteBackup(String name) async {
    if (!await confirmAction(
      context,
      title: '删除这个本地备份？',
      message: '$name 将从网关永久删除，无法撤销。',
      dangerous: true,
      confirmLabel: '删除备份',
    )) {
      return;
    }
    await widget.state.api.deleteBackup(name);
    await _load();
  }

  Future<void> _checkUpdate() async {
    try {
      final update = await widget.state.api.checkUpdate(force: true);
      if (mounted) setState(() => _update = update);
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _applyUpdate() async {
    if (!await confirmAction(
      context,
      title: '安装网关更新？',
      message: '更新会备份当前版本并重建服务。通话、短信和 VoWiFi 会暂时中断。',
    )) {
      return;
    }
    await widget.state.api.applyUpdate();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UpdateProgress(api: widget.state.api),
    );
    await _load();
  }

  Future<void> _maintenance(String action, String title, String impact) async {
    if (!await confirmAction(
      context,
      title: title,
      message: impact,
      dangerous: action == 'restart_host',
    )) {
      return;
    }
    try {
      await widget.state.api.maintenance(action);
      if (mounted) _toast('操作已提交。');
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

JsonMap _nested(JsonMap root, String key) =>
    root[key] is Map ? Map<String, dynamic>.from(root[key] as Map) : {};
JsonMap _patchNested(JsonMap root, String key, JsonMap patch) => {
  ...root,
  key: {..._nested(root, key), ...patch},
};

class _SettingsList extends StatelessWidget {
  const _SettingsList({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(22), children: children);
}

class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({
    required this.value,
    required this.themeMode,
    required this.onTheme,
    required this.onChanged,
  });
  final JsonMap value;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;
  final ValueChanged<JsonMap> onChanged;
  @override
  Widget build(BuildContext context) {
    final defaults = _nested(value, 'device_defaults');
    return _SettingsList(
      children: [
        SectionCard(
          title: '应用外观',
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_rounded),
                label: Text('跟随系统'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('浅色'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('深色'),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (selection) => onTheme(selection.first),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '默认设备行为',
          subtitle: '仅用于新发现设备，不覆盖已有线路的独立期望状态。',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('新模块默认启用 4G'),
                value: defaults['cellular_enabled'] == true,
                onChanged: (next) => onChanged(
                  _patchNested(value, 'device_defaults', {
                    'cellular_enabled': next,
                  }),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('新线路默认启用 VoWiFi'),
                value: defaults['vowifi_enabled'] != false,
                onChanged: (next) => onChanged(
                  _patchNested(value, 'device_defaults', {
                    'vowifi_enabled': next,
                  }),
                ),
              ),
              TextFormField(
                initialValue: value['timezone']?.toString(),
                decoration: const InputDecoration(
                  labelText: '时区',
                  hintText: 'Europe/Berlin',
                ),
                onChanged: (next) => onChanged({...value, 'timezone': next}),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WebSettings extends StatelessWidget {
  const _WebSettings({required this.value, required this.onChanged});
  final JsonMap value;
  final ValueChanged<JsonMap> onChanged;
  @override
  Widget build(BuildContext context) {
    final tls = _nested(value, 'tls');
    return _SettingsList(
      children: [
        SectionCard(
          title: '局域网监听',
          subtitle: '手机只连接 Rust 配对服务公布的 HTTPS 地址；不要直接暴露到公网。',
          child: Column(
            children: [
              TextFormField(
                initialValue: value['bind']?.toString() ?? '0.0.0.0',
                decoration: const InputDecoration(labelText: '监听地址'),
                onChanged: (next) => onChanged({...value, 'bind': next}),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: (value['http_port'] ?? 8443).toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'HTTPS 端口'),
                onChanged: (next) => onChanged({
                  ...value,
                  'http_port': int.tryParse(next) ?? 8443,
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'TLS 证书',
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: tls['mode']?.toString() ?? 'self-signed',
                decoration: const InputDecoration(labelText: '证书模式'),
                items: const [
                  DropdownMenuItem(
                    value: 'self-signed',
                    child: Text('安装级自签名证书'),
                  ),
                  DropdownMenuItem(value: 'manual', child: Text('手动证书')),
                ],
                onChanged: (next) =>
                    onChanged(_patchNested(value, 'tls', {'mode': next})),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: tls['domain']?.toString(),
                decoration: const InputDecoration(labelText: '域名'),
                onChanged: (next) =>
                    onChanged(_patchNested(value, 'tls', {'domain': next})),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: tls['cert_path']?.toString(),
                decoration: const InputDecoration(labelText: '证书路径'),
                onChanged: (next) =>
                    onChanged(_patchNested(value, 'tls', {'cert_path': next})),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: tls['key_path']?.toString(),
                decoration: const InputDecoration(labelText: '私钥路径'),
                onChanged: (next) =>
                    onChanged(_patchNested(value, 'tls', {'key_path': next})),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoiceSettings extends StatelessWidget {
  const _VoiceSettings({required this.value, required this.onChanged});
  final JsonMap value;
  final ValueChanged<JsonMap> onChanged;
  @override
  Widget build(BuildContext context) {
    final retry = _nested(value, 'retry');
    final rekey = _nested(value, 'rekey');
    return _SettingsList(
      children: [
        SectionCard(
          title: '通话与恢复',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: '响铃超时（秒）',
                      value: value['ring_timeout'] ?? 35,
                      onChanged: (next) =>
                          onChanged({...value, 'ring_timeout': next}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumberField(
                      label: '最大重试次数',
                      value: retry['max'] ?? 3,
                      onChanged: (next) => onChanged(
                        _patchNested(value, 'retry', {'max': next}),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: '每次重试间隔（秒）',
                      value: retry['interval'] ?? 30,
                      onChanged: (next) => onChanged(
                        _patchNested(value, 'retry', {'interval': next}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumberField(
                      label: 'Rekey（分钟）',
                      value: rekey['minutes'] ?? 30,
                      onChanged: (next) => onChanged(
                        _patchNested(value, 'rekey', {'minutes': next}),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '语音留言',
          subtitle: '无人接听时由网关录音；录音只保存在网关本地。主动拒接不会录音。',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('新线路默认启用语音留言'),
                value: value['vm_enabled'] == true,
                onChanged: (next) => onChanged({...value, 'vm_enabled': next}),
              ),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: '接听前响铃（秒）',
                      value: value['vm_ring_seconds'] ?? 25,
                      onChanged: (next) =>
                          onChanged({...value, 'vm_ring_seconds': next}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumberField(
                      label: '最大留言长度（秒）',
                      value: value['vm_max_seconds'] ?? 120,
                      onChanged: (next) =>
                          onChanged({...value, 'vm_max_seconds': next}),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SecuritySettings extends StatefulWidget {
  const _SecuritySettings({
    required this.value,
    required this.status,
    required this.onChanged,
    required this.onPassword,
  });
  final JsonMap value;
  final JsonMap status;
  final ValueChanged<JsonMap> onChanged;
  final Future<void> Function(String, String) onPassword;
  @override
  State<_SecuritySettings> createState() => _SecuritySettingsState();
}

class _SecuritySettingsState extends State<_SecuritySettings> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final security = _nested(widget.value, 'security');
    final live = _nested(widget.status, 'security');
    return _SettingsList(
      children: [
        SectionCard(
          title: '连接安全',
          child: Column(
            children: [
              _SettingFact(
                label: 'HTTPS',
                value: live['https'] == true ? '已启用' : '未启用',
              ),
              _SettingFact(
                label: '证书模式',
                value: live['certificate_mode'] ?? '—',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('记录管理员操作审计'),
                value: security['audit_enabled'] != false,
                onChanged: (next) => widget.onChanged(
                  _patchNested(widget.value, 'security', {
                    'audit_enabled': next,
                  }),
                ),
              ),
              TextFormField(
                initialValue: (security['trusted_proxies'] as List?)?.join(
                  ', ',
                ),
                decoration: const InputDecoration(labelText: '可信反向代理（逗号分隔）'),
                onChanged: (next) => widget.onChanged(
                  _patchNested(widget.value, 'security', {
                    'trusted_proxies': next
                        .split(',')
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty)
                        .toList(),
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '修改管理员密码',
          child: Column(
            children: [
              TextField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(labelText: '当前密码'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新密码（至少 10 个字符）'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: '确认新密码'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    if (next.text.length < 10 || next.text != confirm.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('新密码至少 10 个字符，且两次输入必须一致。'),
                        ),
                      );
                      return;
                    }
                    widget.onPassword(current.text, next.text);
                  },
                  child: const Text('修改密码'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BackupUpdateSettings extends StatelessWidget {
  const _BackupUpdateSettings({
    required this.settings,
    required this.status,
    required this.update,
    required this.onChanged,
    required this.onCreateBackup,
    required this.onDeleteBackup,
    required this.onCheckUpdate,
    required this.onApplyUpdate,
  });
  final JsonMap settings;
  final JsonMap status;
  final JsonMap update;
  final ValueChanged<JsonMap> onChanged;
  final VoidCallback onCreateBackup;
  final ValueChanged<String> onDeleteBackup;
  final VoidCallback onCheckUpdate;
  final VoidCallback onApplyUpdate;
  @override
  Widget build(BuildContext context) {
    final backups = status['backups'] is List
        ? status['backups'] as List
        : const [];
    final updates = _nested(settings, 'updates');
    return _SettingsList(
      children: [
        SectionCard(
          title: '本地备份',
          subtitle: '备份保留在网关，由宿主文件权限保护，不通过浏览器自动下载。',
          trailing: FilledButton.tonalIcon(
            onPressed: onCreateBackup,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('创建备份'),
          ),
          child: backups.isEmpty
              ? const Text('没有本地备份。')
              : Column(
                  children: [
                    for (final item in backups.whereType<Map>())
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.archive_outlined),
                        title: Text(item['name'].toString()),
                        subtitle: Text(
                          '${_bytes(item['size'])} · ${_date(item['created_at'])}',
                        ),
                        trailing: IconButton(
                          onPressed: () =>
                              onDeleteBackup(item['name'].toString()),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '软件更新',
          trailing: OutlinedButton.icon(
            onPressed: onCheckUpdate,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('检查更新'),
          ),
          child: Column(
            children: [
              _SettingFact(label: '当前版本', value: status['version'] ?? '—'),
              _SettingFact(label: '最新版本', value: update['latest'] ?? '—'),
              if (update['update_available'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton.icon(
                    onPressed: onApplyUpdate,
                    icon: const Icon(Icons.system_update_alt_rounded),
                    label: const Text('查看并安装更新'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '更新策略',
          subtitle: '自动安装仍受 update-policy.json 的版本与 not_before 许可约束。',
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: updates['update_mode']?.toString() ?? 'automatic',
                decoration: const InputDecoration(labelText: '更新方式'),
                items: const [
                  DropdownMenuItem(value: 'automatic', child: Text('自动更新')),
                  DropdownMenuItem(value: 'notify', child: Text('仅通知')),
                ],
                onChanged: (next) => onChanged(
                  _patchNested(settings, 'updates', {'update_mode': next}),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: updates['version_scope']?.toString() ?? 'main',
                decoration: const InputDecoration(labelText: '版本范围'),
                items: const [
                  DropdownMenuItem(value: 'main', child: Text('仅主版本')),
                  DropdownMenuItem(value: 'all', child: Text('所有版本')),
                ],
                onChanged: (next) => onChanged(
                  _patchNested(settings, 'updates', {'version_scope': next}),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: updates['proxy_mode']?.toString() ?? 'auto',
                decoration: const InputDecoration(labelText: '下载连接'),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('自动：直连后代理库')),
                  DropdownMenuItem(value: 'direct', child: Text('仅直连')),
                  DropdownMenuItem(value: 'library', child: Text('指定代理')),
                ],
                onChanged: (next) => onChanged(
                  _patchNested(settings, 'updates', {'proxy_mode': next}),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    await widgetSave(context, settings);
                  },
                  child: const Text('保存更新策略'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> widgetSave(BuildContext context, JsonMap settings) async {
    final state = context.findAncestorStateOfType<_SystemPageState>();
    await state?._save();
  }

  static String _bytes(Object? value) {
    final bytes = num.tryParse(value?.toString() ?? '') ?? 0;
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';
  }

  static String _date(Object? value) {
    final seconds = num.tryParse(value?.toString() ?? '');
    return seconds == null
        ? '—'
        : DateTime.fromMillisecondsSinceEpoch(
            (seconds * 1000).round(),
          ).toLocal().toString();
  }
}

class _MaintenanceSettings extends StatelessWidget {
  const _MaintenanceSettings({required this.onAction});
  final Future<void> Function(String, String, String) onAction;
  @override
  Widget build(BuildContext context) => _SettingsList(
    children: [
      SectionCard(
        title: '例行维护',
        subtitle: '刷新运行状态，不重启 Mac。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton(
              onPressed: () => onAction(
                'restart_lines',
                '重启所有 VoWiFi 线路？',
                '所有线路会重建 SIM、ePDG 与 IMS 连接，来电和短信会暂时中断。',
              ),
              child: const Text('重启所有 VoWiFi 线路'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => onAction(
                'refresh_egress',
                '刷新国家出口？',
                '将重新生成并验证国家 TUN 和 UDP 出口。',
              ),
              child: const Text('刷新国家出口'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => onAction(
                'clear_notification_history',
                '清空通知历史？',
                '删除网关本地通知投递历史。',
              ),
              child: const Text('清空通知历史'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: '重启',
        subtitle: '按中断范围从小到大排列。宿主机重启会让全部线路离线。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton(
              onPressed: () => onAction(
                'restart_control',
                '重启控制面？',
                '管理界面会短暂断开，但正在进行的通话不应被终止。',
              ),
              child: const Text('重启控制面'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () =>
                  onAction('restart_services', '重启全部网关服务？', '全部通信服务会暂时中断。'),
              child: const Text('重启全部网关服务'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => onAction(
                'restart_host',
                '重启 Mac 网关的 Linux VM？',
                '全部线路、通话、短信和网络出口都会中断，直到 Linux VM 和容器重新启动。',
              ),
              child: const Text('重启 Linux VM / 网关宿主'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final Object value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: value.toString(),
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    onChanged: (value) => onChanged(int.tryParse(value) ?? 0),
  );
}

class _SettingFact extends StatelessWidget {
  const _SettingFact({required this.label, required this.value});
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          displayValue(value),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _UpdateProgress extends StatefulWidget {
  const _UpdateProgress({required this.api});
  final GatewayApi api;
  @override
  State<_UpdateProgress> createState() => _UpdateProgressState();
}

class _UpdateProgressState extends State<_UpdateProgress> {
  JsonMap _progress = {'state': 'running', 'phase': 'requested'};
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    try {
      final value = await widget.api.updateProgress();
      if (!mounted) return;
      setState(() => _progress = value);
      if (['success', 'failed', 'stalled'].contains(value['state'])) {
        _timer?.cancel();
      }
    } on Object {
      // The control plane restarts near the end of a successful update. Keep the
      // dialog open and let the next bounded poll observe it coming back.
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = ['success', 'failed', 'stalled'].contains(_progress['state']);
    return AlertDialog(
      title: Text(done ? '更新结果' : '正在更新网关'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!done) const LinearProgressIndicator(),
            const SizedBox(height: 14),
            Text('阶段：${_progress['phase'] ?? 'requested'}'),
            if (_progress['target'] != null)
              Text('目标版本：${_progress['target']}'),
            if (_progress['error'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _progress['error'].toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (!done)
          TextButton(
            onPressed: () async {
              await widget.api.cancelUpdate();
            },
            child: const Text('取消更新'),
          ),
        if (done)
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
      ],
    );
  }
}
