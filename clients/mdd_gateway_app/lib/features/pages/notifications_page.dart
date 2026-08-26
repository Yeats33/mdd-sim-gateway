import 'package:flutter/material.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.state, super.key});

  final GatewayState state;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  JsonMap _settings = {};
  JsonMap _deliveries = {'pending': <dynamic>[], 'history': <dynamic>[]};
  bool _deliveryTab = false;
  bool _saving = false;

  static const _events = <String, String>{
    'incoming_call': '来电',
    'missed_call': '未接来电',
    'voicemail_received': '新语音留言',
    'incoming_sms': '收到短信',
    'host_alert': '宿主机告警',
    'number_changed': '线路号码变化',
    'line_unrecoverable': '线路无法恢复',
    'keepalive_result': '保号结果',
    'balance_low': '余额不足',
    'software_update': '软件更新',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final webhook = _channel('webhook');
    final telegram = _channel('telegram');
    final pushplus = _channel('pushplus');
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.notifications_active_outlined),
              label: Text('通知渠道'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.receipt_long_outlined),
              label: Text('投递记录'),
            ),
          ],
          selected: {_deliveryTab},
          onSelectionChanged: (value) {
            setState(() => _deliveryTab = value.first);
            if (_deliveryTab) _loadDeliveries();
          },
        ),
        const SizedBox(height: 16),
        if (_deliveryTab)
          _DeliveryLog(
            value: _deliveries,
            onRefresh: _loadDeliveries,
            onClear: _clearDeliveries,
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final width = wide
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: width,
                    child: _WebhookCard(
                      value: webhook,
                      events: _events,
                      onChanged: (patch) => _setChannel('webhook', patch),
                      onTest: () => _test('webhook'),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _TelegramCard(
                      value: telegram,
                      events: _events,
                      countries: _proxyCountries(),
                      onChanged: (patch) => _setChannel('telegram', patch),
                      onTest: () => _test('telegram'),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _PushPlusCard(
                      value: pushplus,
                      events: _events,
                      onChanged: (patch) => _setChannel('pushplus', patch),
                      onTest: () => _test('pushplus'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _advanced,
                icon: const Icon(Icons.data_object_rounded),
                label: const Text('高级配置'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('保存通知设置'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  JsonMap _channel(String key) => _settings[key] is Map
      ? Map<String, dynamic>.from(_settings[key] as Map)
      : {};
  void _setChannel(String key, JsonMap patch) => setState(
    () => _settings = {
      ..._settings,
      key: {..._channel(key), ...patch},
    },
  );
  List<String> _proxyCountries() {
    final proxy = _settings['proxy'];
    final exits = proxy is Map ? proxy['exits'] : null;
    return exits is Map ? exits.keys.map((key) => key.toString()).toList() : [];
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.state.api.settings(),
        widget.state.api.notificationDeliveries(),
      ]);
      if (mounted) {
        setState(() {
          _settings = results[0];
          _deliveries = results[1];
        });
      }
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _loadDeliveries() async {
    try {
      final value = await widget.state.api.notificationDeliveries();
      if (mounted) setState(() => _deliveries = value);
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _clearDeliveries() async {
    if (!await confirmAction(
      context,
      title: '清空通知投递记录？',
      message: '将删除已完成和待重试通知的本地历史。',
      dangerous: true,
      confirmLabel: '清空',
    )) {
      return;
    }
    await widget.state.api.clearNotificationDeliveries();
    await _loadDeliveries();
  }

  Future<void> _test(String channel) async {
    try {
      switch (channel) {
        case 'webhook':
          await widget.state.api.testWebhook(_channel(channel));
        case 'telegram':
          await widget.state.api.testTelegram(_channel(channel));
        case 'pushplus':
          await widget.state.api.testPushPlus(_channel(channel));
      }
      if (mounted) _toast('测试通知发送成功。');
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.state.api.saveSettings(_settings);
      if (mounted) _toast('通知设置已保存。');
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _advanced() async {
    final edited = await showJsonEditor(
      context,
      title: '高级通知设置',
      value: {
        'webhook': _channel('webhook'),
        'telegram': _channel('telegram'),
        'pushplus': _channel('pushplus'),
      },
    );
    if (edited != null) setState(() => _settings = {..._settings, ...edited});
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _WebhookCard extends StatelessWidget {
  const _WebhookCard({
    required this.value,
    required this.events,
    required this.onChanged,
    required this.onTest,
  });
  final JsonMap value;
  final Map<String, String> events;
  final ValueChanged<JsonMap> onChanged;
  final VoidCallback onTest;
  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Webhook',
    subtitle: '标准 GET/POST、JSON/Form/Raw 和自定义模板。',
    trailing: Switch(
      value: value['enabled'] == true,
      onChanged: (next) => onChanged({'enabled': next}),
    ),
    child: Column(
      children: [
        TextFormField(
          initialValue: value['url']?.toString(),
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Webhook URL'),
          onChanged: (next) => onChanged({'url': next}),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: value['method']?.toString() ?? 'POST',
                decoration: const InputDecoration(labelText: '方法'),
                items: const [
                  DropdownMenuItem(value: 'POST', child: Text('POST')),
                  DropdownMenuItem(value: 'GET', child: Text('GET')),
                ],
                onChanged: (next) => onChanged({'method': next}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: value['body_mode']?.toString() ?? 'json',
                decoration: const InputDecoration(labelText: '正文格式'),
                items: const [
                  DropdownMenuItem(value: 'json', child: Text('JSON')),
                  DropdownMenuItem(value: 'form', child: Text('Form')),
                  DropdownMenuItem(value: 'raw', child: Text('Raw')),
                ],
                onChanged: (next) => onChanged({'body_mode': next}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: value['headers_json']?.toString() ?? '{}',
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '自定义请求头（JSON）'),
          onChanged: (next) => onChanged({'headers_json': next}),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('验证远端 TLS 证书'),
          value: value['verify_tls'] != false,
          onChanged: (next) => onChanged({'verify_tls': next}),
        ),
        _EventOptions(value: value, labels: events, onChanged: onChanged),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onTest,
            icon: const Icon(Icons.send_outlined),
            label: const Text('发送测试'),
          ),
        ),
      ],
    ),
  );
}

class _TelegramCard extends StatelessWidget {
  const _TelegramCard({
    required this.value,
    required this.events,
    required this.countries,
    required this.onChanged,
    required this.onTest,
  });
  final JsonMap value;
  final Map<String, String> events;
  final List<String> countries;
  final ValueChanged<JsonMap> onChanged;
  final VoidCallback onTest;
  @override
  Widget build(BuildContext context) {
    final mode = value['proxy_mode']?.toString() ?? 'direct';
    return SectionCard(
      title: 'Telegram',
      subtitle: '仅单向通知，不接收远程拨号、短信或挂断命令。',
      trailing: Switch(
        value: value['enabled'] == true,
        onChanged: (next) => onChanged({'enabled': next}),
      ),
      child: Column(
        children: [
          TextFormField(
            initialValue: value['bot_token']?.toString(),
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Bot Token'),
            onChanged: (next) => onChanged({'bot_token': next}),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: value['chat_id']?.toString(),
            decoration: const InputDecoration(labelText: 'Chat / Channel ID'),
            onChanged: (next) => onChanged({'chat_id': next}),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: '连接方式'),
            items: const [
              DropdownMenuItem(value: 'direct', child: Text('直连')),
              DropdownMenuItem(
                value: 'manual',
                child: Text('手动 HTTP/SOCKS 代理'),
              ),
              DropdownMenuItem(value: 'country', child: Text('使用国家出口')),
            ],
            onChanged: (next) => onChanged({'proxy_mode': next}),
          ),
          if (mode == 'manual') ...[
            const SizedBox(height: 10),
            TextFormField(
              initialValue: value['proxy_url']?.toString(),
              decoration: const InputDecoration(labelText: '代理 URL'),
              onChanged: (next) => onChanged({'proxy_url': next}),
            ),
          ],
          if (mode == 'country') ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: countries.contains(value['proxy_country'])
                  ? value['proxy_country']?.toString()
                  : null,
              decoration: const InputDecoration(labelText: '国家出口'),
              items: [
                for (final country in countries)
                  DropdownMenuItem(
                    value: country,
                    child: Text(country.toUpperCase()),
                  ),
              ],
              onChanged: (next) => onChanged({'proxy_country': next}),
            ),
          ],
          _EventOptions(value: value, labels: events, onChanged: onChanged),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onTest,
              icon: const Icon(Icons.send_outlined),
              label: const Text('发送测试'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PushPlusCard extends StatelessWidget {
  const _PushPlusCard({
    required this.value,
    required this.events,
    required this.onChanged,
    required this.onTest,
  });
  final JsonMap value;
  final Map<String, String> events;
  final ValueChanged<JsonMap> onChanged;
  final VoidCallback onTest;
  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'PushPlus',
    subtitle: '通过 PushPlus 官方服务推送。',
    trailing: Switch(
      value: value['enabled'] == true,
      onChanged: (next) => onChanged({'enabled': next}),
    ),
    child: Column(
      children: [
        TextFormField(
          initialValue: value['token']?.toString(),
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Token'),
          onChanged: (next) => onChanged({'token': next}),
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: value['topic']?.toString(),
          decoration: const InputDecoration(labelText: 'Topic（可选）'),
          onChanged: (next) => onChanged({'topic': next}),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: value['template']?.toString() ?? 'html',
                decoration: const InputDecoration(labelText: '模板'),
                items: const [
                  DropdownMenuItem(value: 'html', child: Text('HTML')),
                  DropdownMenuItem(value: 'txt', child: Text('纯文本')),
                  DropdownMenuItem(value: 'markdown', child: Text('Markdown')),
                  DropdownMenuItem(value: 'json', child: Text('JSON')),
                ],
                onChanged: (next) => onChanged({'template': next}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: value['channel']?.toString() ?? 'wechat',
                decoration: const InputDecoration(labelText: '渠道'),
                items: const [
                  DropdownMenuItem(value: 'wechat', child: Text('微信')),
                  DropdownMenuItem(value: 'app', child: Text('App')),
                  DropdownMenuItem(value: 'mail', child: Text('邮件')),
                  DropdownMenuItem(value: 'webhook', child: Text('Webhook')),
                  DropdownMenuItem(value: 'cp', child: Text('企业微信')),
                  DropdownMenuItem(value: 'clawbot', child: Text('ClawBot')),
                ],
                onChanged: (next) => onChanged({'channel': next}),
              ),
            ),
          ],
        ),
        _EventOptions(value: value, labels: events, onChanged: onChanged),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onTest,
            icon: const Icon(Icons.send_outlined),
            label: const Text('发送测试'),
          ),
        ),
      ],
    ),
  );
}

class _EventOptions extends StatelessWidget {
  const _EventOptions({
    required this.value,
    required this.labels,
    required this.onChanged,
  });
  final JsonMap value;
  final Map<String, String> labels;
  final ValueChanged<JsonMap> onChanged;
  @override
  Widget build(BuildContext context) {
    final current = value['events'] is Map
        ? Map<String, dynamic>.from(value['events'] as Map)
        : <String, dynamic>{};
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('转发事件'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 2,
          children: [
            for (final entry in labels.entries)
              FilterChip(
                label: Text(entry.value),
                selected: current[entry.key] != false,
                onSelected: (selected) => onChanged({
                  'events': {...current, entry.key: selected},
                }),
              ),
          ],
        ),
      ],
    );
  }
}

class _DeliveryLog extends StatelessWidget {
  const _DeliveryLog({
    required this.value,
    required this.onRefresh,
    required this.onClear,
  });
  final JsonMap value;
  final VoidCallback onRefresh;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    final pending = value['pending'] is List
        ? value['pending'] as List
        : const [];
    final history = value['history'] is List
        ? value['history'] as List
        : const [];
    return SectionCard(
      title: '投递记录',
      subtitle: '失败投递最多自动重试三次。',
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            onPressed: onRefresh,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: onClear,
            tooltip: '清空',
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      child: pending.isEmpty && history.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: '没有投递记录',
              message: '发送通知后会显示渠道、事件、状态和尝试次数。',
            )
          : Column(
              children: [
                for (final row in [...pending, ...history])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      pending.contains(row)
                          ? Icons.sync_rounded
                          : Icons.check_circle_outline_rounded,
                    ),
                    title: Text('${row['channel']} · ${row['event']}'),
                    subtitle: Text(
                      '${row['status'] ?? 'retrying'} · ${row['attempts'] ?? 0}/3',
                    ),
                    trailing: StatusPill(
                      (row['status'] ?? '重试中').toString(),
                      kind: statusKind(row['status']),
                    ),
                  ),
              ],
            ),
    );
  }
}
