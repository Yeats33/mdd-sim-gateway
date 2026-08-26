import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api/gateway_api.dart';
import '../../core/host/macos_host_service.dart';
import '../../core/state/gateway_state.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({required this.state, super.key});

  final GatewayState state;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _endpoint = TextEditingController();
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  bool _remember = true;
  bool _obscure = true;
  bool _hostBusy = false;
  String? _hostMessage;

  @override
  void initState() {
    super.initState();
    _endpoint.text = widget.state.endpoint?.toString() ?? '';
    _username.text = widget.state.username ?? 'admin';
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.state.endpoint != null;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Brand(),
                          const SizedBox(height: 28),
                          Text(
                            connected
                                ? (widget.state.configured ? '登录网关' : '创建管理员')
                                : '连接 Mac 网关',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            connected
                                ? widget.state.endpoint.toString()
                                : '手机与 Mac 需要位于同一可信局域网。首次连接会核对证书指纹。',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (!connected)
                            ..._connectionFields(context)
                          else
                            ..._loginFields(context),
                          if (widget.state.error case final error?) ...[
                            const SizedBox(height: 16),
                            _ErrorBanner(error),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _connectionFields(BuildContext context) => [
    if (Platform.isMacOS) ...[
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: .38),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.desktop_mac_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '这台 Mac 作为网关主机',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '自动创建 Apple Silicon Linux VM，并在其中安装和管理 Docker 通信引擎。',
              style: TextStyle(fontSize: 12),
            ),
            if (_hostMessage != null) ...[
              const SizedBox(height: 7),
              Text(_hostMessage!, style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 11),
            FilledButton.tonalIcon(
              onPressed: _hostBusy ? null : _setupMacHost,
              icon: _hostBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_outline_rounded),
              label: Text(_hostBusy ? '正在准备网关…' : '设置并启动本机网关'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '或连接另一台网关',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: 18),
    ],
    TextField(
      controller: _endpoint,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: '网关地址',
        hintText: 'https://mdd-gateway.local:8443',
        prefixIcon: Icon(Icons.lan_outlined),
      ),
      onSubmitted: (_) => _connect(),
    ),
    const SizedBox(height: 14),
    Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: widget.state.connecting ? null : _connect,
            icon: widget.state.connecting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link_rounded),
            label: const Text('验证并连接'),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: '扫描 Mac 上的配对二维码',
          onPressed: widget.state.connecting ? null : _scanQr,
          icon: const Icon(Icons.qr_code_scanner_rounded),
        ),
      ],
    ),
    const SizedBox(height: 18),
    const _PrivacyNote(),
  ];

  List<Widget> _loginFields(BuildContext context) => [
    TextField(
      controller: _username,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username],
      decoration: const InputDecoration(
        labelText: '用户名',
        prefixIcon: Icon(Icons.person_outline_rounded),
      ),
    ),
    const SizedBox(height: 14),
    TextField(
      controller: _password,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        labelText: '密码',
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
      onSubmitted: (_) => _authenticate(),
    ),
    const SizedBox(height: 4),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _remember,
      title: const Text('在这台设备上保持登录'),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (value) => setState(() => _remember = value ?? true),
    ),
    const SizedBox(height: 8),
    FilledButton.icon(
      onPressed: widget.state.connecting ? null : _authenticate,
      icon: widget.state.connecting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.arrow_forward_rounded),
      label: Text(widget.state.configured ? '登录' : '创建并登录'),
    ),
    const SizedBox(height: 10),
    TextButton.icon(
      onPressed: widget.state.connecting ? null : widget.state.disconnect,
      icon: const Icon(Icons.swap_horiz_rounded),
      label: const Text('更换网关'),
    ),
  ];

  Future<void> _connect({String? pairedFingerprint}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final observed =
          pairedFingerprint ??
          await widget.state.inspectEndpoint(_endpoint.text);
      if (!mounted) return;
      if (observed != null && pairedFingerprint == null) {
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.verified_user_outlined),
            title: const Text('核对网关证书'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请与 Mac App 上显示的 SHA-256 指纹逐段核对。只有完全一致时才信任。'),
                const SizedBox(height: 16),
                SelectableText(
                  GatewayApi.displayFingerprint(observed),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('不一致'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('完全一致'),
              ),
            ],
          ),
        );
        if (accepted != true) return;
      }
      await widget.state.configureEndpoint(
        _endpoint.text,
        fingerprint: observed,
      );
    } on Object {
      // GatewayState exposes the actionable error in the card.
    }
  }

  Future<void> _setupMacHost() async {
    setState(() {
      _hostBusy = true;
      _hostMessage = '正在启动本机 Rust 宿主服务…';
    });
    try {
      final host = MacHostService();
      await host.ensureRunning();
      var status = await host.status();
      if (!mounted) return;
      if (status.vm == 'not_installed') {
        setState(() => _hostMessage = '正在创建 Linux VM 并安装 Docker 网关；首次运行需要几分钟…');
        await host.install();
      } else if (status.vm == 'stopped') {
        setState(() => _hostMessage = '正在启动 Linux VM…');
        await host.start();
      } else if (status.vm == 'broken') {
        throw const HttpException('Lima VM 状态不可用，请检查安装日志。');
      }
      for (var attempt = 0; attempt < 60; attempt++) {
        status = await host.status();
        if (status.gatewayReady) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!status.gatewayReady) {
        throw const HttpException('Linux VM 已启动，但网关控制面尚未就绪。');
      }
      _endpoint.text = status.gatewayUrl;
      setState(() => _hostMessage = '本机网关已就绪，正在核对 HTTPS 证书…');
      await _connect();
    } on Object catch (error) {
      if (mounted) setState(() => _hostMessage = error.toString());
    } finally {
      if (mounted) setState(() => _hostBusy = false);
    }
  }

  Future<void> _authenticate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    try {
      if (widget.state.configured) {
        await widget.state.login(
          _username.text.trim(),
          _password.text,
          remember: _remember,
        );
      } else {
        await widget.state.setup(
          _username.text.trim(),
          _password.text,
          remember: _remember,
        );
      }
    } on Object {
      // GatewayState exposes the actionable error in the card.
    }
  }

  Future<void> _scanQr() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _QrScannerSheet(),
    );
    if (result == null || !mounted) return;
    final parsed = Uri.tryParse(result);
    String? fingerprint;
    if (parsed?.scheme == 'mdd') {
      final host = parsed?.queryParameters['url'];
      fingerprint = parsed?.queryParameters['fingerprint'];
      if (host != null) _endpoint.text = host;
    } else {
      _endpoint.text = result;
    }
    await _connect(pairedFingerprint: fingerprint);
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6F66FF), Color(0xFF4540C7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.sim_card_rounded, color: Colors.white),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MDD Sim Gateway',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              Text('4G + VoWiFi · 本地优先', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text('管理会话只保存在系统安全存储中，不进入网关备份或 WebDAV。')),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: .45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(
        painter: _SignalPainter(Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  const _SignalPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: .08);
    for (var radius = 100.0; radius < size.longestSide; radius += 86) {
      canvas.drawCircle(
        Offset(size.width * .85, size.height * .1),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _QrScannerSheet extends StatefulWidget {
  const _QrScannerSheet();

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              '扫描 Mac App 的配对二维码',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                if (_handled) return;
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (value == null) return;
                _handled = true;
                Navigator.pop(context, value);
              },
            ),
          ),
        ],
      ),
    );
  }
}
