import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sip_ua/sip_ua.dart';

import '../../core/api/gateway_api.dart';
import '../../core/state/gateway_state.dart';
import '../../core/widgets/gateway_widgets.dart';

class CallsPage extends StatefulWidget {
  const CallsPage({required this.state, super.key});

  final GatewayState state;

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> implements SipUaHelperListener {
  final _number = TextEditingController();
  final SIPUAHelper _sip = SIPUAHelper();
  final AudioPlayer _voicemailPlayer = AudioPlayer();
  String? _lineId;
  String _registration = '未连接';
  Call? _call;
  CallStateEnum? _callState;
  bool _muted = false;
  bool _dialing = false;
  String _domain = 'localhost';
  List<JsonMap> _history = [];
  List<JsonMap> _voicemails = [];

  @override
  void initState() {
    super.initState();
    _sip.addSipUaHelperListener(this);
    _lineId = widget.state.instances.firstOrNull?['id']?.toString();
    if (_lineId != null) _loadLine();
  }

  @override
  void didUpdateWidget(covariant CallsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lineId == null && widget.state.instances.isNotEmpty) {
      _lineId = widget.state.instances.first['id']?.toString();
      _loadLine();
    }
  }

  @override
  void dispose() {
    _sip.removeSipUaHelperListener(this);
    _sip.stop();
    _voicemailPlayer.dispose();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.instances.isEmpty) {
      return const EmptyState(
        icon: Icons.phone_disabled_outlined,
        title: '没有可通话线路',
        message: '先完成一条启用 WebRTC 的 VoWiFi 线路配置。',
      );
    }
    final active =
        _call != null &&
        !{CallStateEnum.ENDED, CallStateEnum.FAILED}.contains(_callState);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        LinePicker(
          lines: widget.state.instances,
          value: _lineId,
          onChanged: (value) {
            _sip.stop();
            setState(() {
              _lineId = value;
              _registration = '连接中';
              _call = null;
              _callState = null;
              _history = [];
              _voicemails = [];
            });
            _loadLine();
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 880;
            final dialer = _DialerCard(
              number: _number,
              registration: _registration,
              call: _call,
              callState: _callState,
              incoming: _call?.session.direction == Direction.incoming,
              muted: _muted,
              dialing: _dialing,
              onDigit: _digit,
              onBackspace: _backspace,
              onCall: _placeCall,
              onAnswer: _answer,
              onReject: _reject,
              onHangup: _hangup,
              onMute: _toggleMute,
              onDtmf: (digit) => _call?.sendDTMF(digit),
            );
            final history = _HistoryCard(
              history: _history,
              voicemails: _voicemails,
              onDial: (number) {
                _number.text = number;
                _placeCall();
              },
              onDeleteCall: _deleteCall,
              onClearCalls: _clearCalls,
              onPlayVoicemail: _playVoicemail,
              onDeleteVoicemail: _deleteVoicemail,
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 390, child: dialer),
                      const SizedBox(width: 14),
                      Expanded(child: history),
                    ],
                  )
                : Column(
                    children: [dialer, const SizedBox(height: 14), history],
                  );
          },
        ),
        if (!active) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: '蜂窝模块拨号',
            subtitle: '实验性控制通道只操作 ModemManager 呼叫对象，不代表手机拥有该蜂窝通话的音频。',
            child: Row(
              children: [
                const Expanded(
                  child: Text('手机麦克风和听筒通话请使用上方 VoWiFi WebRTC 软电话。'),
                ),
                OutlinedButton.icon(
                  onPressed: _placeCellularCall,
                  icon: const Icon(Icons.cell_tower_rounded),
                  label: const Text('通过模块拨号'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _loadLine() async {
    final line = _lineId;
    if (line == null) return;
    try {
      final results = await Future.wait([
        widget.state.api.softphone(line),
        widget.state.api.calls(line),
        widget.state.api.voicemails(line),
      ]);
      if (!mounted || line != _lineId) return;
      final provisioning = results[0];
      setState(() {
        _history = _list(results[1], 'calls');
        _voicemails = _list(results[2], 'voicemails');
      });
      if (provisioning['enabled'] == true) {
        _startSip(provisioning);
      } else {
        setState(() => _registration = '线路未启用软电话');
      }
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  void _startSip(JsonMap provisioning) {
    final host =
        provisioning['host']?.toString() ?? widget.state.endpoint?.host;
    final username = provisioning['username']?.toString();
    final password = provisioning['password']?.toString();
    final port = provisioning['ws_port']?.toString() ?? '8089';
    if (host == null || username == null || password == null) {
      setState(() => _registration = '软电话配置不完整');
      return;
    }
    final domain = provisioning['domain']?.toString() ?? host;
    _domain = domain;
    final settings = UaSettings()
      ..transportType = TransportType.WS
      ..webSocketUrl = 'wss://$host:$port/ws'
      ..uri = 'sip:$username@$domain'
      ..authorizationUser = username
      ..password = password
      ..displayName = 'MDD Mobile'
      ..host = domain
      ..realm = provisioning['realm']?.toString()
      ..contact_uri = 'sip:$username@$domain;transport=wss'
      ..register = true
      ..sessionTimers = false
      ..dtmfMode = DtmfMode.RFC2833
      ..userAgent = 'MDD Sim Gateway Native';
    // The WSS endpoint uses the installation certificate already confirmed on pairing.
    // sip_ua currently supports self-signed WSS as a boolean rather than a fingerprint hook.
    settings.webSocketSettings.allowBadCertificate =
        widget.state.certificateSha256 != null;
    setState(() => _registration = '连接中');
    _sip.start(settings);
  }

  Future<void> _placeCall() async {
    final number = _number.text.trim();
    if (number.isEmpty || _dialing) return;
    final microphone = await Permission.microphone.request();
    if (!microphone.isGranted) {
      if (mounted) _toast('需要麦克风权限才能拨打 VoWiFi 电话。');
      return;
    }
    if (Platform.isAndroid) {
      // Android 12+ protects Bluetooth headset routing separately. On older
      // releases this permission reports granted without a user prompt.
      await Permission.bluetoothConnect.request();
    }
    setState(() => _dialing = true);
    try {
      final ok = await _sip.call(
        'sip:${Uri.encodeComponent(number)}@${_sipDomain()}',
        voiceOnly: true,
      );
      if (!ok && mounted) _toast('软电话尚未注册。');
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    } finally {
      if (mounted) setState(() => _dialing = false);
    }
  }

  String _sipDomain() => _domain;

  Future<void> _placeCellularCall() async {
    final line = _lineId;
    final number = _number.text.trim();
    if (line == null || number.isEmpty) return;
    if (!await confirmAction(
      context,
      title: '通过蜂窝模块拨号？',
      message: '这只控制模块的呼叫对象；手机不会自动获得该通话的音频。',
    )) {
      return;
    }
    try {
      await widget.state.api.cellularCall(line, number);
      if (mounted) _toast('已向蜂窝模块提交拨号。');
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  void _answer() => _call?.answer(_sip.buildCallOptions(true));
  void _reject() => _call?.hangup({'status_code': 603});
  void _hangup() => _call?.hangup();

  void _toggleMute() {
    if (_call == null) return;
    if (_muted) {
      _call!.unmute(true, false);
    } else {
      _call!.mute(true, false);
    }
    setState(() => _muted = !_muted);
  }

  void _digit(String digit) {
    _number.text += digit;
    if (_callState == CallStateEnum.CONFIRMED) _call?.sendDTMF(digit);
    setState(() {});
  }

  void _backspace() {
    final value = _number.text;
    if (value.isNotEmpty) _number.text = value.substring(0, value.length - 1);
    setState(() {});
  }

  Future<void> _deleteCall(Object? id) async {
    final line = _lineId;
    if (line == null || id == null) return;
    await widget.state.mutate(
      (api) => api.deleteCalls(line, {
        'ids': [id],
      }),
    );
    await _reloadHistory();
  }

  Future<void> _clearCalls() async {
    final line = _lineId;
    if (line == null || _history.isEmpty) return;
    if (!await confirmAction(
      context,
      title: '清空通话记录？',
      message: '只清除线路 $line 的本地通话历史，无法撤销。',
      dangerous: true,
      confirmLabel: '全部删除',
    )) {
      return;
    }
    await widget.state.mutate((api) => api.deleteCalls(line, {'all': true}));
    await _reloadHistory();
  }

  Future<void> _reloadHistory() async {
    final line = _lineId;
    if (line == null) return;
    final results = await Future.wait([
      widget.state.api.calls(line),
      widget.state.api.voicemails(line),
    ]);
    if (mounted && line == _lineId) {
      setState(() {
        _history = _list(results[0], 'calls');
        _voicemails = _list(results[1], 'voicemails');
      });
    }
  }

  Future<void> _playVoicemail(JsonMap voicemail) async {
    final line = _lineId;
    final id = voicemail['id'];
    if (line == null || id == null) return;
    try {
      final bytes = await widget.state.api.download(
        '/api/instances/${Uri.encodeComponent(line)}/voicemails/$id/audio',
      );
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/mdd-voicemail-$line-$id.wav');
      await file.writeAsBytes(bytes, flush: true);
      await _voicemailPlayer.play(DeviceFileSource(file.path));
      await widget.state.api.markVoicemailListened(line, id);
      await _reloadHistory();
    } on Object catch (error) {
      if (mounted) _toast(error.toString());
    }
  }

  Future<void> _deleteVoicemail(Object? id) async {
    final line = _lineId;
    if (line == null || id == null) return;
    if (!await confirmAction(
      context,
      title: '删除语音留言？',
      message: '将从网关本地永久删除这段录音。',
      dangerous: true,
      confirmLabel: '删除',
    )) {
      return;
    }
    await widget.state.mutate(
      (api) => api.deleteVoicemails(line, {
        'ids': [id],
      }),
    );
    await _reloadHistory();
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

  @override
  void callStateChanged(Call call, CallState state) {
    if (!mounted) return;
    setState(() {
      _call = call;
      _callState = state.state;
      if ({CallStateEnum.ENDED, CallStateEnum.FAILED}.contains(state.state)) {
        _muted = false;
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!mounted || _call != call) return;
          setState(() {
            _call = null;
            _callState = null;
          });
          _reloadHistory();
        });
      }
    });
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    if (!mounted) return;
    setState(() {
      _registration = switch (state.state) {
        RegistrationStateEnum.REGISTERED => '已注册',
        RegistrationStateEnum.REGISTRATION_FAILED => '注册失败',
        RegistrationStateEnum.UNREGISTERED => '未注册',
        _ => '连接中',
      };
    });
  }

  @override
  void transportStateChanged(TransportState state) {
    if (!mounted) return;
    if (state.state == TransportStateEnum.DISCONNECTED) {
      setState(() => _registration = '连接断开');
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {
    event.accept?.call(_sip.buildCallOptions(true));
  }
}

class _DialerCard extends StatelessWidget {
  const _DialerCard({
    required this.number,
    required this.registration,
    required this.call,
    required this.callState,
    required this.incoming,
    required this.muted,
    required this.dialing,
    required this.onDigit,
    required this.onBackspace,
    required this.onCall,
    required this.onAnswer,
    required this.onReject,
    required this.onHangup,
    required this.onMute,
    required this.onDtmf,
  });

  final TextEditingController number;
  final String registration;
  final Call? call;
  final CallStateEnum? callState;
  final bool incoming;
  final bool muted;
  final bool dialing;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onCall;
  final VoidCallback onAnswer;
  final VoidCallback onReject;
  final VoidCallback onHangup;
  final VoidCallback onMute;
  final ValueChanged<String> onDtmf;

  @override
  Widget build(BuildContext context) {
    final active =
        call != null &&
        !{CallStateEnum.ENDED, CallStateEnum.FAILED}.contains(callState);
    final isIncoming = active && incoming;
    final label = switch (callState) {
      CallStateEnum.CALL_INITIATION => isIncoming ? '来电' : '正在拨号',
      CallStateEnum.PROGRESS => '正在响铃',
      CallStateEnum.ACCEPTED || CallStateEnum.CONFIRMED => '通话中',
      CallStateEnum.FAILED => '通话失败',
      CallStateEnum.ENDED => '通话结束',
      _ => '准备拨号',
    };
    return SectionCard(
      title: active ? label : '手机软电话',
      trailing: StatusPill(
        registration,
        kind: registration == '已注册'
            ? StatusKind.success
            : registration.contains('失败') || registration.contains('断开')
            ? StatusKind.danger
            : StatusKind.warning,
      ),
      child: Column(
        children: [
          TextField(
            controller: number,
            enabled: !active,
            keyboardType: TextInputType.phone,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
            decoration: const InputDecoration(
              hintText: '+86…',
              border: InputBorder.none,
              filled: false,
            ),
          ),
          const SizedBox(height: 10),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['*', '0', '#'],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final digit in row)
                    _DialKey(
                      digit: digit,
                      onTap: () => active ? onDtmf(digit) : onDigit(digit),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (!active)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filled(
                  onPressed: dialing ? null : onCall,
                  iconSize: 30,
                  padding: const EdgeInsets.all(16),
                  icon: const Icon(Icons.call_rounded),
                ),
                const SizedBox(width: 18),
                IconButton(
                  onPressed: onBackspace,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ],
            )
          else if (isIncoming)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FilledButton.icon(
                  onPressed: onAnswer,
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('接听'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: onReject,
                  icon: const Icon(Icons.call_end_rounded),
                  label: const Text('拒接'),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  onPressed: onMute,
                  icon: Icon(muted ? Icons.mic_off_rounded : Icons.mic_rounded),
                  tooltip: muted ? '取消静音' : '静音',
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: onHangup,
                  icon: const Icon(Icons.call_end_rounded),
                  tooltip: '挂断',
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DialKey extends StatelessWidget {
  const _DialKey({required this.digit, required this.onTap});

  final String digit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 66,
        height: 55,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          digit,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.history,
    required this.voicemails,
    required this.onDial,
    required this.onDeleteCall,
    required this.onClearCalls,
    required this.onPlayVoicemail,
    required this.onDeleteVoicemail,
  });

  final List<JsonMap> history;
  final List<JsonMap> voicemails;
  final ValueChanged<String> onDial;
  final ValueChanged<Object?> onDeleteCall;
  final VoidCallback onClearCalls;
  final ValueChanged<JsonMap> onPlayVoicemail;
  final ValueChanged<Object?> onDeleteVoicemail;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '通话记录与语音留言',
      trailing: history.isEmpty
          ? null
          : IconButton(
              onPressed: onClearCalls,
              tooltip: '清空通话记录',
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: '通话记录'),
                Tab(text: '语音留言'),
              ],
            ),
            SizedBox(
              height: 420,
              child: TabBarView(
                children: [
                  history.isEmpty
                      ? const EmptyState(
                          icon: Icons.history_rounded,
                          title: '没有通话记录',
                          message: '拨出或接听电话后会显示在这里。',
                        )
                      : ListView.builder(
                          itemCount: history.length,
                          itemBuilder: (context, index) {
                            final item = history[index];
                            final peer =
                                (item['peer'] ?? item['number'] ?? '未知号码')
                                    .toString();
                            return ListTile(
                              leading: Icon(
                                item['direction'] == 'in'
                                    ? Icons.call_received_rounded
                                    : Icons.call_made_rounded,
                              ),
                              title: Text(peer),
                              subtitle: Text(
                                '${item['disposition'] ?? item['status'] ?? ''} · ${item['duration'] ?? 0}s',
                              ),
                              onTap: () => onDial(peer),
                              trailing: IconButton(
                                onPressed: () => onDeleteCall(item['id']),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            );
                          },
                        ),
                  voicemails.isEmpty
                      ? const EmptyState(
                          icon: Icons.voicemail_outlined,
                          title: '没有语音留言',
                          message: '启用线路语音留言后，未接来电录音保存在网关本地。',
                        )
                      : ListView.builder(
                          itemCount: voicemails.length,
                          itemBuilder: (context, index) {
                            final item = voicemails[index];
                            return ListTile(
                              leading: Icon(
                                item['listened'] == true
                                    ? Icons.mark_email_read_outlined
                                    : Icons.voicemail_rounded,
                              ),
                              title: Text(
                                (item['peer'] ?? item['number'] ?? '未知号码')
                                    .toString(),
                              ),
                              subtitle: Text('${item['duration'] ?? 0}s'),
                              onTap: () => onPlayVoicemail(item),
                              trailing: IconButton(
                                onPressed: () => onDeleteVoicemail(item['id']),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
