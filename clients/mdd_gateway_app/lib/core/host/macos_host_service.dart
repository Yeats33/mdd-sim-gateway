import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class MacHostStatus {
  const MacHostStatus({
    required this.vm,
    required this.gatewayReady,
    required this.gatewayUrl,
  });

  final String vm;
  final bool gatewayReady;
  final String gatewayUrl;

  factory MacHostStatus.fromJson(Map<String, dynamic> value) => MacHostStatus(
    vm: value['vm']?.toString() ?? 'broken',
    gatewayReady: value['gateway_ready'] == true,
    gatewayUrl: value['gateway_url']?.toString() ?? 'https://127.0.0.1:8443',
  );
}

class MacHostService {
  MacHostService({Uri? endpoint})
    : endpoint = endpoint ?? Uri.parse('http://127.0.0.1:48630');

  final Uri endpoint;
  String? _token;
  Process? _process;

  Future<void> ensureRunning() async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('Mac host service is available only on macOS.');
    }
    if (await _healthy()) {
      await _loadToken();
      return;
    }
    final resources = _resourcesDirectory();
    final support = await getApplicationSupportDirectory();
    final stateDir = Directory(path.join(support.path, 'hostd'));
    await stateDir.create(recursive: true);
    final hostd = _firstExisting([
      Platform.environment['MDD_HOSTD_BIN'],
      path.join(resources, 'mdd-hostd'),
      path.join(
        Directory.current.path,
        'native',
        'mdd-hostd',
        'target',
        'release',
        'mdd-hostd',
      ),
      path.join(
        Directory.current.path,
        'native',
        'mdd-hostd',
        'target',
        'debug',
        'mdd-hostd',
      ),
    ]);
    if (hostd == null) {
      throw const FileSystemException('找不到随 App 打包的 mdd-hostd。');
    }
    final limaTemplate = _firstExisting([
      Platform.environment['MDD_LIMA_TEMPLATE'],
      path.join(resources, 'mdd-vm.yaml'),
      path.join(
        Directory.current.path,
        'native',
        'mdd-hostd',
        'templates',
        'mdd-vm.yaml',
      ),
    ]);
    final configuredSource = Platform.environment['MDD_SOURCE_DIR'];
    final bundledSource = path.join(resources, 'gateway-source');
    final source = configuredSource != null
        ? _firstExisting([configuredSource])
        : await _stageBundledSource(bundledSource, support.path) ??
              _firstExisting([Directory.current.path]);
    final limactl = _firstExisting([
      Platform.environment['MDD_LIMA_BIN'],
      path.join(resources, 'limactl'),
      '/opt/homebrew/bin/limactl',
      '/usr/local/bin/limactl',
    ]);
    if (limaTemplate == null || source == null) {
      throw const FileSystemException('Mac 网关资源不完整。');
    }
    if (limactl == null) {
      throw const FileSystemException('尚未安装 Lima；正式 DMG 会内置经校验的 limactl。');
    }
    final arguments = [
      '--state-dir',
      stateDir.path,
      '--source-dir',
      source,
      '--lima-template',
      limaTemplate,
      '--lima-bin',
      limactl,
    ];
    final logFile = File(path.join(stateDir.path, 'hostd.log'));
    final logSink = logFile.openWrite(mode: FileMode.writeOnlyAppend);
    logSink.writeln(
      '[${DateTime.now().toIso8601String()}] launching bundled mdd-hostd',
    );
    var startupTail = '';
    void recordOutput(String stream, String chunk) {
      final entry = '[$stream] $chunk';
      logSink.write(entry);
      startupTail += entry;
      if (startupTail.length > 4000) {
        startupTail = startupTail.substring(startupTail.length - 4000);
      }
    }

    try {
      _process = await Process.start(
        hostd,
        arguments,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (error) {
      logSink.writeln('[spawn] $error');
      await logSink.flush();
      await logSink.close();
      throw HttpException(
        '无法启动 mdd-hostd：${error.message}。日志：${logFile.path}',
      );
    }
    final stdoutDone = _process!.stdout
        .transform(utf8.decoder)
        .forEach((chunk) => recordOutput('stdout', chunk));
    final stderrDone = _process!.stderr
        .transform(utf8.decoder)
        .forEach((chunk) => recordOutput('stderr', chunk));
    int? exitCode;
    unawaited(
      _process!.exitCode.then((value) async {
        await Future.wait([stdoutDone, stderrDone]);
        exitCode = value;
        logSink.writeln('[exit] status=$value');
        await logSink.flush();
        await logSink.close();
      }),
    );
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await _healthy()) {
        await logSink.flush();
        await _loadToken();
        return;
      }
      if (exitCode != null) {
        final detail = startupTail.trim();
        throw HttpException(
          'mdd-hostd 已提前退出（状态 $exitCode）。'
          '${detail.isEmpty ? '' : ' $detail'} 日志：${logFile.path}',
        );
      }
    }
    _process!.kill(ProcessSignal.sigterm);
    await logSink.flush();
    final detail = startupTail.trim();
    throw HttpException(
      'mdd-hostd 启动超时。${detail.isEmpty ? '' : ' $detail'} '
      '日志：${logFile.path}',
    );
  }

  Future<MacHostStatus> status() async =>
      MacHostStatus.fromJson(await _request('GET', '/v1/status'));

  Future<Map<String, dynamic>> install() => _request('POST', '/v1/install');
  Future<Map<String, dynamic>> start() => _request('POST', '/v1/start');
  Future<Map<String, dynamic>> stop() => _request('POST', '/v1/stop');
  Future<Map<String, dynamic>> restart() => _request('POST', '/v1/restart');
  Future<Map<String, dynamic>> reload() => _request('POST', '/v1/reload');
  Future<Map<String, dynamic>> pairing({String? lanHost}) => _request(
    'POST',
    '/v1/pairing',
    headers: lanHost == null ? null : {'X-MDD-LAN-Host': lanHost},
  );

  Future<bool> _healthy() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1);
      final request = await client.getUrl(endpoint.resolve('/v1/health'));
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      await response.drain<void>();
      client.close(force: true);
      return response.statusCode == HttpStatus.ok;
    } on Object {
      return false;
    }
  }

  Future<void> _loadToken() async {
    final support = await getApplicationSupportDirectory();
    final tokenFile = File(path.join(support.path, 'hostd', 'hostd.token'));
    _token = (await tokenFile.readAsString()).trim();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String requestPath, {
    Map<String, String>? headers,
  }) async {
    if (_token == null) await _loadToken();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.openUrl(
        method,
        endpoint.resolve(requestPath),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      headers?.forEach(request.headers.set);
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(text.isEmpty ? response.reasonPhrase : text);
      }
      final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      return Map<String, dynamic>.from(decoded as Map);
    } finally {
      client.close(force: true);
    }
  }

  String _resourcesDirectory() {
    final executableDir = path.dirname(Platform.resolvedExecutable);
    return path.normalize(path.join(executableDir, '..', 'Resources'));
  }

  Future<String?> _stageBundledSource(
    String bundledSource,
    String supportDirectory,
  ) async {
    if (!Directory(bundledSource).existsSync()) return null;
    final versionFile = File(path.join(bundledSource, 'VERSION'));
    final rawVersion = versionFile.existsSync()
        ? versionFile.readAsStringSync().trim()
        : 'development';
    final version = rawVersion.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final staged = path.join(supportDirectory, 'gateway-source-$version');
    if (Directory(staged).existsSync()) return staged;
    final result = await Process.run('/usr/bin/ditto', [bundledSource, staged]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        '无法将网关源码准备到 Application Support：${result.stderr}',
        staged,
      );
    }
    return staged;
  }

  String? _firstExisting(List<String?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null &&
          candidate.isNotEmpty &&
          FileSystemEntity.typeSync(candidate) !=
              FileSystemEntityType.notFound) {
        return path.absolute(candidate);
      }
    }
    return null;
  }
}
