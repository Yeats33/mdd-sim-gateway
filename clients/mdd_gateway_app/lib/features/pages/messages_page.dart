import 'package:flutter/material.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({required this.state, super.key});

  final GatewayState state;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _recipient = TextEditingController();
  final _composer = TextEditingController();
  String? _lineId;
  String? _peer;
  String _transport = 'auto';
  List<JsonMap> _threads = [];
  List<JsonMap> _messages = [];
  List<JsonMap> _binary = [];
  bool _loading = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _lineId = widget.state.instances.firstOrNull?['id']?.toString();
    if (_lineId != null) _loadThreads();
  }

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lineId == null && widget.state.instances.isNotEmpty) {
      _lineId = widget.state.instances.first['id']?.toString();
      _loadThreads();
    }
  }

  @override
  void dispose() {
    _recipient.dispose();
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.instances.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: '没有可用线路',
        message: '先在设备页完成 SIM 线路配置，再收发短信。',
      );
    }
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          LinePicker(
            lines: widget.state.instances,
            value: _lineId,
            onChanged: (value) {
              setState(() {
                _lineId = value;
                _peer = null;
                _threads = [];
                _messages = [];
                _binary = [];
              });
              _loadThreads();
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 720) {
                  return _peer == null
                      ? _ThreadPane(
                          threads: _threads,
                          binary: _binary,
                          loading: _loading,
                          onNew: _newMessage,
                          onOpen: _openThread,
                          onDelete: _deleteThread,
                          onClear: _clearAll,
                        )
                      : _ConversationPane(
                          peer: _peer!,
                          messages: _messages,
                          recipient: _recipient,
                          composer: _composer,
                          transport: _transport,
                          sending: _sending,
                          onTransport: (value) =>
                              setState(() => _transport = value),
                          onSend: _send,
                          onBack: () => setState(() => _peer = null),
                          onDeleteMessage: _deleteMessage,
                        );
                }
                return Row(
                  children: [
                    SizedBox(
                      width: 300,
                      child: _ThreadPane(
                        threads: _threads,
                        binary: _binary,
                        loading: _loading,
                        selectedPeer: _peer,
                        onNew: _newMessage,
                        onOpen: _openThread,
                        onDelete: _deleteThread,
                        onClear: _clearAll,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ConversationPane(
                        peer: _peer,
                        messages: _messages,
                        recipient: _recipient,
                        composer: _composer,
                        transport: _transport,
                        sending: _sending,
                        onTransport: (value) =>
                            setState(() => _transport = value),
                        onSend: _send,
                        onDeleteMessage: _deleteMessage,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadThreads() async {
    final line = _lineId;
    if (line == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.state.api.threads(line),
        widget.state.api.binarySms(line),
      ]);
      if (!mounted || line != _lineId) return;
      setState(() {
        _threads = _list(results[0], 'threads');
        _binary = _list(results[1], 'payloads');
      });
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openThread(String peer) async {
    final line = _lineId;
    if (line == null) return;
    setState(() {
      _peer = peer;
      _recipient.text = peer;
      _messages = [];
      _loading = true;
    });
    try {
      final result = await widget.state.api.messages(line, peer);
      if (mounted && line == _lineId && peer == _peer) {
        setState(() => _messages = _list(result, 'messages'));
      }
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _newMessage() {
    setState(() {
      _peer = '';
      _messages = [];
      _recipient.clear();
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final line = _lineId;
    final to = _peer?.isNotEmpty == true ? _peer! : _recipient.text.trim();
    final text = _composer.text.trim();
    if (line == null || to.isEmpty || text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final result = await widget.state.api.sendSms(
        line,
        to,
        text,
        transport: _transport,
      );
      if (!mounted) return;
      if (result['ok'] == false) {
        _toast(
          result['uncertain'] == true
              ? '短信提交超时，送达状态未知；请勿自动重试，以免产生重复计费。'
              : '短信发送失败：${result['error'] ?? '未知错误'}',
        );
      }
      _composer.clear();
      await _loadThreads();
      await _openThread(to);
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteMessage(Object? id) async {
    final line = _lineId;
    if (line == null || id == null) return;
    if (!await confirmAction(
      context,
      title: '删除这条短信？',
      message: '只删除网关本地保存的这一条记录。',
      dangerous: true,
      confirmLabel: '删除',
    )) {
      return;
    }
    await widget.state.mutate(
      (api) => api.deleteMessages(line, {
        'ids': [id],
      }),
    );
    if (_peer case final peer? when peer.isNotEmpty) await _openThread(peer);
  }

  Future<void> _deleteThread(String peer) async {
    final line = _lineId;
    if (line == null) return;
    if (!await confirmAction(
      context,
      title: '删除整个会话？',
      message: '将删除线路 $line 与 $peer 的全部本地短信记录。',
      dangerous: true,
      confirmLabel: '删除会话',
    )) {
      return;
    }
    await widget.state.mutate(
      (api) => api.deleteMessages(line, {'peer': peer}),
    );
    if (_peer == peer) {
      setState(() {
        _peer = null;
        _messages = [];
      });
    }
    await _loadThreads();
  }

  Future<void> _clearAll() async {
    final line = _lineId;
    if (line == null || _threads.isEmpty) return;
    if (!await confirmAction(
      context,
      title: '清空这条线路的全部短信？',
      message: '将删除线路 $line 的全部本地短信和会话记录，无法撤销。',
      dangerous: true,
      confirmLabel: '全部删除',
    )) {
      return;
    }
    await widget.state.mutate((api) => api.deleteMessages(line, {'all': true}));
    setState(() {
      _peer = null;
      _messages = [];
    });
    await _loadThreads();
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

class _ThreadPane extends StatelessWidget {
  const _ThreadPane({
    required this.threads,
    required this.binary,
    required this.loading,
    required this.onNew,
    required this.onOpen,
    required this.onDelete,
    required this.onClear,
    this.selectedPeer,
  });

  final List<JsonMap> threads;
  final List<JsonMap> binary;
  final bool loading;
  final String? selectedPeer;
  final VoidCallback onNew;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onNew,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新短信'),
                  ),
                ),
                if (threads.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onClear,
                    tooltip: '清空全部会话',
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ],
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: threads.isEmpty && !loading
                ? const EmptyState(
                    icon: Icons.mark_chat_unread_outlined,
                    title: '没有短信会话',
                    message: '收到或发出第一条短信后，会话会显示在这里。',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                    itemCount: threads.length + (binary.isEmpty ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == threads.length) {
                        return _BinaryPayloads(payloads: binary);
                      }
                      final thread = threads[index];
                      final peer = thread['peer']?.toString() ?? '';
                      return ListTile(
                        selected: selectedPeer == peer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        leading: CircleAvatar(
                          child: Text(
                            peer.isEmpty ? '?' : peer.characters.last,
                          ),
                        ),
                        title: Text(
                          peer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          (thread['last_body'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          onPressed: () => onDelete(peer),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                        ),
                        onTap: () => onOpen(peer),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.peer,
    required this.messages,
    required this.recipient,
    required this.composer,
    required this.transport,
    required this.sending,
    required this.onTransport,
    required this.onSend,
    required this.onDeleteMessage,
    this.onBack,
  });

  final String? peer;
  final List<JsonMap> messages;
  final TextEditingController recipient;
  final TextEditingController composer;
  final String transport;
  final bool sending;
  final ValueChanged<String> onTransport;
  final VoidCallback onSend;
  final ValueChanged<Object?> onDeleteMessage;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (peer == null) {
      return const Card(
        margin: EdgeInsets.zero,
        child: EmptyState(
          icon: Icons.forum_outlined,
          title: '选择一个会话',
          message: '或点击“新短信”输入收件人号码。',
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Expanded(
                  child: peer!.isNotEmpty
                      ? Text(
                          peer!,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        )
                      : TextField(
                          controller: recipient,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: '收件人号码',
                            isDense: true,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: messages.isEmpty
                ? const EmptyState(
                    icon: Icons.mark_chat_read_outlined,
                    title: '没有短信',
                    message: '在下方输入内容开始这个会话。',
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, reversedIndex) {
                      final message =
                          messages[messages.length - 1 - reversedIndex];
                      return _MessageBubble(
                        message: message,
                        onDelete: () => onDeleteMessage(message['id']),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('发送方式：', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      value: transport,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(
                          value: 'auto',
                          child: Text('自动（VoWiFi 优先）'),
                        ),
                        DropdownMenuItem(
                          value: 'vowifi',
                          child: Text('VoWiFi'),
                        ),
                        DropdownMenuItem(
                          value: 'cellular',
                          child: Text('蜂窝模块'),
                        ),
                      ],
                      onChanged: sending
                          ? null
                          : (value) {
                              if (value != null) onTransport(value);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: composer,
                        enabled: !sending,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(hintText: '输入短信内容…'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: sending ? null : onSend,
                      tooltip: '发送短信',
                      icon: sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onDelete});

  final JsonMap message;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final outgoing = message['direction'] == 'out';
    final status = message['status']?.toString();
    final failed = status == 'failed';
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onDelete,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: failed
                ? Theme.of(context).colorScheme.errorContainer
                : outgoing
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(15).copyWith(
              bottomRight: outgoing ? const Radius.circular(4) : null,
              bottomLeft: outgoing ? null : const Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                (message['body'] ?? '').toString(),
                style: TextStyle(
                  color: outgoing && !failed
                      ? Theme.of(context).colorScheme.onPrimary
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  _time(message['ts']),
                  if (message['transport'] == 'cellular') '4G',
                  ?status,
                ].join(' · '),
                style: TextStyle(
                  fontSize: 10,
                  color: outgoing && !failed
                      ? Theme.of(
                          context,
                        ).colorScheme.onPrimary.withValues(alpha: .75)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _time(Object? timestamp) {
    final seconds = num.tryParse(timestamp?.toString() ?? '');
    if (seconds == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _BinaryPayloads extends StatelessWidget {
  const _BinaryPayloads({required this.payloads});

  final List<JsonMap> payloads;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.data_object_rounded),
      title: const Text('非文本载荷', style: TextStyle(fontSize: 13)),
      trailing: Text('${payloads.length}'),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            '这些内容发给 SIM 或应用，而不是普通短信会话；网关保留原始数据，不会丢弃。',
            style: TextStyle(fontSize: 11),
          ),
        ),
        for (final payload in payloads)
          ListTile(
            dense: true,
            title: Text((payload['peer'] ?? '未知来源').toString()),
            subtitle: SelectableText(
              (payload['body_hex'] ?? '—').toString(),
              maxLines: 3,
            ),
          ),
      ],
    );
  }
}
