import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

typedef JsonMap = Map<String, dynamic>;

class GatewayApiException implements Exception {
  const GatewayApiException(this.message, {this.status, this.data});

  final String message;
  final int? status;
  final Object? data;

  @override
  String toString() => message;
}

class GatewayApi {
  GatewayApi({
    required Uri baseUri,
    String? trustedCertificateSha256,
    this.sessionCookie,
    this.csrfToken,
  }) : baseUri = _normalizeBaseUri(baseUri),
       trustedCertificateSha256 = _normalizeFingerprint(
         trustedCertificateSha256,
       );

  final Uri baseUri;
  final String? trustedCertificateSha256;
  String? sessionCookie;
  String? csrfToken;

  static Uri _normalizeBaseUri(Uri uri) {
    final normalized = uri.hasScheme ? uri : Uri.parse('https://$uri');
    if (normalized.scheme != 'https' &&
        !(normalized.scheme == 'http' && normalized.isLoopback)) {
      throw const GatewayApiException('网关必须使用 HTTPS；仅本机开发地址可以使用 HTTP。');
    }
    return normalized.replace(path: '', query: null, fragment: null);
  }

  static String? _normalizeFingerprint(String? value) {
    final normalized = value
        ?.replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
        .toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String certificateSha256(X509Certificate certificate) {
    final body = certificate.pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s'), '');
    return sha256.convert(base64Decode(body)).toString();
  }

  static String displayFingerprint(String value) {
    final normalized = _normalizeFingerprint(value) ?? '';
    return [
      for (var i = 0; i < normalized.length; i += 2)
        normalized.substring(
          i,
          i + 2 > normalized.length ? normalized.length : i + 2,
        ),
    ].join(':').toUpperCase();
  }

  static Future<String?> inspectCertificate(Uri rawBaseUri) async {
    final baseUri = _normalizeBaseUri(rawBaseUri);
    if (baseUri.scheme != 'https') return null;
    X509Certificate? observed;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..badCertificateCallback = (certificate, host, port) {
        if (host == baseUri.host &&
            port == (baseUri.hasPort ? baseUri.port : 443)) {
          observed = certificate;
          return true;
        }
        return false;
      };
    try {
      final request = await client.getUrl(baseUri.resolve('/api/auth/status'));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
    return observed == null ? null : certificateSha256(observed!);
  }

  HttpClient _newClient() {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    final fingerprint = trustedCertificateSha256;
    if (fingerprint != null) {
      client.badCertificateCallback = (certificate, host, port) {
        if (host != baseUri.host ||
            port != (baseUri.hasPort ? baseUri.port : 443)) {
          return false;
        }
        return certificateSha256(certificate) == fingerprint;
      };
    }
    return client;
  }

  Uri uri(String path, [Map<String, Object?>? query]) {
    final encoded = query == null
        ? null
        : <String, String>{
            for (final entry in query.entries)
              if (entry.value != null) entry.key: entry.value.toString(),
          };
    return baseUri.resolve(path).replace(queryParameters: encoded);
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
  }) async {
    final client = _newClient();
    try {
      final request = await client.openUrl(method, uri(path, query));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (sessionCookie case final cookie?) {
        request.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      if (csrfToken case final csrf?
          when !const {'GET', 'HEAD', 'OPTIONS'}.contains(method)) {
        request.headers.set('X-MDD-CSRF-Token', csrf);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );
      if (response.cookies.isNotEmpty) {
        final liveCookies = response.cookies
            .where((cookie) => cookie.value.isNotEmpty && cookie.maxAge != 0)
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .toList();
        if (liveCookies.isNotEmpty) sessionCookie = liveCookies.join('; ');
        if (response.cookies.any(
          (cookie) => cookie.name == 'mdd_session' && cookie.value.isEmpty,
        )) {
          sessionCookie = null;
        }
      }
      final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, chunk) => builder..add(chunk),
      );
      final payloadBytes = bytes.takeBytes();
      final text = utf8.decode(payloadBytes, allowMalformed: true);
      dynamic data;
      try {
        data = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      } on FormatException {
        data = <String, dynamic>{'raw': text};
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == HttpStatus.unauthorized) csrfToken = null;
        final detail = data is Map ? data['detail'] : null;
        final message = detail is Map
            ? detail['message']?.toString()
            : detail?.toString();
        throw GatewayApiException(
          message ??
              (data is Map ? data['error']?.toString() : null) ??
              response.reasonPhrase,
          status: response.statusCode,
          data: data,
        );
      }
      return data;
    } on TimeoutException {
      throw const GatewayApiException('连接网关超时。');
    } on HandshakeException catch (error) {
      throw GatewayApiException('无法验证网关证书：$error');
    } on SocketException catch (error) {
      throw GatewayApiException('无法连接网关：${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> download(String path) async {
    final client = _newClient();
    try {
      final request = await client.getUrl(uri(path));
      if (sessionCookie case final cookie?) {
        request.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw GatewayApiException(
          response.reasonPhrase,
          status: response.statusCode,
        );
      }
      return Uint8List.fromList(
        await response.expand((chunk) => chunk).toList(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Stream<JsonMap> events() async* {
    final wsUri = baseUri.replace(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: const {'auth_close': '1'},
    );
    final socket = await WebSocket.connect(
      wsUri.toString(),
      headers: sessionCookie == null
          ? null
          : <String, dynamic>{HttpHeaders.cookieHeader: sessionCookie},
      customClient: _newClient(),
    );
    await for (final message in socket) {
      if (message is! String) continue;
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) yield decoded;
    }
    if (socket.closeCode == 4401) {
      csrfToken = null;
      throw const GatewayApiException('登录已失效。', status: 401);
    }
  }

  Future<JsonMap> _map(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
  }) async => Map<String, dynamic>.from(
    await request(method, path, body: body, query: query) as Map,
  );

  Future<JsonMap> authStatus() => _map('GET', '/api/auth/status');
  Future<JsonMap> authSetup(String username, String password, bool remember) =>
      _map(
        'POST',
        '/api/auth/setup',
        body: {
          'username': username,
          'password': password,
          'remember': remember,
        },
      );
  Future<JsonMap> authLogin(String username, String password, bool remember) =>
      _map(
        'POST',
        '/api/auth/login',
        body: {
          'username': username,
          'password': password,
          'remember': remember,
        },
      );
  Future<JsonMap> authLogout() => _map('POST', '/api/auth/logout', body: {});
  Future<JsonMap> authPassword(String current, String next) => _map(
    'POST',
    '/api/auth/password',
    body: {'current_password': current, 'new_password': next},
  );

  Future<JsonMap> devices() => _map('GET', '/api/devices');
  Future<JsonMap> patchDeviceCapabilities(String id, JsonMap patch) => _map(
    'PATCH',
    '/api/devices/${Uri.encodeComponent(id)}/capabilities',
    body: patch,
  );
  Future<JsonMap> deviceCellular(String id) =>
      _map('GET', '/api/devices/${Uri.encodeComponent(id)}/cellular');
  Future<JsonMap> deviceDiagnostics(String id) => _map(
    'POST',
    '/api/devices/${Uri.encodeComponent(id)}/diagnostics',
    body: {},
  );
  Future<JsonMap> saveDeviceHardware(String id, JsonMap patch) => _map(
    'PUT',
    '/api/devices/${Uri.encodeComponent(id)}/hardware',
    body: patch,
  );
  Future<JsonMap> deleteDevice(String id) =>
      _map('DELETE', '/api/devices/${Uri.encodeComponent(id)}');

  Future<JsonMap> readers() => _map('GET', '/api/readers');
  Future<JsonMap> detect([int readerIndex = 0]) =>
      _map('GET', '/api/sim/detect', query: {'reader_index': readerIndex});
  Future<JsonMap> verifyPin(String pin, int readerIndex, {String? reader}) =>
      _map(
        'POST',
        '/api/sim/verify-pin',
        body: {'pin': pin, 'reader_index': readerIndex, 'reader': ?reader},
      );
  Future<JsonMap> changePin(String oldPin, String newPin, int readerIndex) =>
      _map(
        'POST',
        '/api/sim/change-pin',
        body: {'old': oldPin, 'new': newPin, 'reader_index': readerIndex},
      );
  Future<JsonMap> setPinEnabled(String pin, bool enabled, int readerIndex) =>
      _map(
        'POST',
        '/api/sim/pin-enabled',
        body: {'pin': pin, 'enabled': enabled, 'reader_index': readerIndex},
      );

  Future<JsonMap> settings() => _map('GET', '/api/settings');
  Future<JsonMap> saveSettings(JsonMap patch) =>
      _map('PUT', '/api/settings', body: patch);
  Future<JsonMap> egressStatus() => _map('GET', '/api/egress/status');
  Future<JsonMap> testEgress(String country) => _map(
    'POST',
    '/api/egress/${Uri.encodeComponent(country)}/test',
    body: {},
  );
  Future<JsonMap> testProxyProfile(String id, [JsonMap? profile]) => _map(
    'POST',
    '/api/egress/profile/${Uri.encodeComponent(id)}/test',
    body: profile ?? {},
  );
  Future<JsonMap> refreshEgress() =>
      _map('POST', '/api/egress/refresh', body: {});
  Future<JsonMap> testWebhook([JsonMap? config]) =>
      _map('POST', '/api/notifications/webhook/test', body: config ?? {});
  Future<JsonMap> testTelegram([JsonMap? config]) =>
      _map('POST', '/api/notifications/telegram/test', body: config ?? {});
  Future<JsonMap> testPushPlus([JsonMap? config]) =>
      _map('POST', '/api/notifications/pushplus/test', body: config ?? {});
  Future<JsonMap> notificationDeliveries([int limit = 100]) =>
      _map('GET', '/api/notifications/deliveries', query: {'limit': limit});
  Future<JsonMap> clearNotificationDeliveries() =>
      _map('DELETE', '/api/notifications/deliveries');

  Future<JsonMap> systemStatus() => _map('GET', '/api/system/status');
  Future<JsonMap> clearHostAlerts() =>
      _map('DELETE', '/api/system/host-alerts');
  Future<JsonMap> checkUpdate({bool force = false}) => _map(
    'GET',
    '/api/system/update/check',
    query: force ? {'force': true} : null,
  );
  Future<JsonMap> repositoryStars({bool force = false}) => _map(
    'GET',
    '/api/system/repository/stars',
    query: force ? {'force': true} : null,
  );
  Future<JsonMap> applyUpdate() =>
      _map('POST', '/api/system/update/apply', body: {});
  Future<JsonMap> updateProgress() =>
      _map('GET', '/api/system/update/progress');
  Future<JsonMap> cancelUpdate() =>
      _map('POST', '/api/system/update/cancel', body: {});
  Future<JsonMap> createBackup() =>
      _map('POST', '/api/system/backups', body: {});
  Future<JsonMap> deleteBackup(String name) =>
      _map('DELETE', '/api/system/backups/${Uri.encodeComponent(name)}');
  Future<JsonMap> maintenance(String action) =>
      _map('POST', '/api/system/maintenance', body: {'action': action});
  Future<JsonMap> restartProgress() =>
      _map('GET', '/api/system/maintenance/restart-progress');
  Future<Uint8List> supportBundle() =>
      download('/api/diagnostics/support-bundle');

  Future<JsonMap> instances() => _map('GET', '/api/instances');
  Future<JsonMap> cards() => _map('GET', '/api/cards');
  Future<JsonMap> portsSuggest() => _map('GET', '/api/ports/suggest');
  Future<JsonMap> provision(JsonMap body) =>
      _map('POST', '/api/provision', body: body);
  Future<JsonMap> saveInstance(JsonMap body) =>
      _map('POST', '/api/instances', body: body);
  Future<JsonMap> setLineCountry(String id, String country) => _map(
    'PUT',
    '/api/instances/${Uri.encodeComponent(id)}/country',
    body: {'country': country},
  );
  Future<JsonMap> deleteInstance(String id, {bool deleteHistory = true}) =>
      _map(
        'DELETE',
        '/api/instances/${Uri.encodeComponent(id)}',
        query: {'delete_history': deleteHistory, 'confirm_id': id},
      );
  Future<JsonMap> startLine(String id, [JsonMap? body]) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/start',
    body: body ?? {},
  );
  Future<JsonMap> stopLine(String id) =>
      _map('POST', '/api/instances/${Uri.encodeComponent(id)}/stop', body: {});
  Future<JsonMap> reprovision(String id, [JsonMap? body]) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/reprovision',
    body: body ?? {},
  );
  Future<JsonMap> clearPin(String id) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/pin/clear',
    body: {},
  );
  Future<JsonMap> lineStatus(String id) =>
      _map('GET', '/api/instances/${Uri.encodeComponent(id)}/status');
  Future<JsonMap> lineAvailability(String id) =>
      _map('GET', '/api/instances/${Uri.encodeComponent(id)}/availability');
  Future<JsonMap> logs(String id, {int tail = 300}) => _map(
    'GET',
    '/api/instances/${Uri.encodeComponent(id)}/logs',
    query: {'tail': tail},
  );
  Future<JsonMap> registerLine(String id) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/register',
    body: {},
  );

  Future<JsonMap> threads(String id) =>
      _map('GET', '/api/instances/${Uri.encodeComponent(id)}/messages/threads');
  Future<JsonMap> messages(String id, String peer) => _map(
    'GET',
    '/api/instances/${Uri.encodeComponent(id)}/messages/${Uri.encodeComponent(peer)}',
  );
  Future<JsonMap> binarySms(String id) =>
      _map('GET', '/api/instances/${Uri.encodeComponent(id)}/messages/binary');
  Future<JsonMap> sendSms(
    String id,
    String to,
    String text, {
    String transport = 'auto',
  }) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/sms/send',
    body: {'to': to, 'body': text, 'transport': transport},
  );
  Future<JsonMap> deleteMessages(String id, JsonMap selection) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/messages/delete',
    body: selection,
  );

  Future<JsonMap> allowance(String id) =>
      _map('GET', '/api/instances/${Uri.encodeComponent(id)}/allowance');
  Future<JsonMap> saveAllowance(String id, JsonMap body) => _map(
    'PUT',
    '/api/instances/${Uri.encodeComponent(id)}/allowance',
    body: body,
  );
  Future<JsonMap> allowanceQueryRule(String id) => _map(
    'GET',
    '/api/instances/${Uri.encodeComponent(id)}/allowance/query-rule',
  );
  Future<JsonMap> saveAllowanceQueryRule(String id, JsonMap body) => _map(
    'PUT',
    '/api/instances/${Uri.encodeComponent(id)}/allowance/query-rule',
    body: body,
  );
  Future<JsonMap> resetAllowanceQueryRule(String id) => _map(
    'DELETE',
    '/api/instances/${Uri.encodeComponent(id)}/allowance/query-rule',
  );
  Future<JsonMap> queryAllowance(String id, {String transport = 'auto'}) =>
      _map(
        'POST',
        '/api/instances/${Uri.encodeComponent(id)}/allowance/query',
        body: {'transport': transport},
      );
  Future<JsonMap> keepalive(String id) =>
      _map('GET', '/api/instances/${Uri.encodeComponent(id)}/keepalive');
  Future<JsonMap> saveKeepalive(String id, JsonMap body) => _map(
    'PUT',
    '/api/instances/${Uri.encodeComponent(id)}/keepalive',
    body: body,
  );
  Future<JsonMap> keepaliveSummary() => _map('GET', '/api/keepalive/summary');
  Future<JsonMap> runKeepalive(String id) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/keepalive/run',
    body: {},
  );

  Future<JsonMap> voicemails(String id) =>
      _map('GET', '/api/instances/${Uri.encodeComponent(id)}/voicemails');
  Uri voicemailAudioUri(String id, Object voicemailId) => uri(
    '/api/instances/${Uri.encodeComponent(id)}/voicemails/$voicemailId/audio',
  );
  Future<JsonMap> markVoicemailListened(String id, Object voicemailId) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/voicemails/$voicemailId/listened',
    body: {},
  );
  Future<JsonMap> deleteVoicemails(String id, JsonMap selection) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/voicemails/delete',
    body: selection,
  );
  Future<JsonMap> calls(String id) =>
      _map('GET', '/api/instances/${Uri.encodeComponent(id)}/calls');
  Future<JsonMap> deleteCalls(String id, JsonMap selection) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/calls/delete',
    body: selection,
  );
  Future<JsonMap> call(
    String id,
    String to, {
    String fromEndpoint = 'webrtc',
  }) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/call',
    body: {'to': to, 'from_endpoint': fromEndpoint},
  );
  Future<JsonMap> hangup(String id) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/hangup',
    body: {},
  );
  Future<JsonMap> cellularCall(String id, String to) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/cellular-call',
    body: {'to': to},
  );
  Future<JsonMap> cellularCallStatus(String id) => _map(
    'GET',
    '/api/instances/${Uri.encodeComponent(id)}/cellular-call/status',
  );
  Future<JsonMap> cellularCallHangup(String id) => _map(
    'POST',
    '/api/instances/${Uri.encodeComponent(id)}/cellular-call/hangup',
    body: {},
  );
  Future<JsonMap> softphone(String id) =>
      _map('GET', '/api/instances/${Uri.encodeComponent(id)}/softphone');

  Map<String, Object?> _readerQuery(Object reader) =>
      reader is String ? {'reader': reader} : {'reader_index': reader};
  JsonMap _readerBody(Object reader, [JsonMap? extra]) => {
    if (reader is String) 'reader': reader else 'reader_index': reader,
    ...?extra,
  };

  Future<JsonMap> esimStatus() => _map('GET', '/api/esim/status');
  Future<JsonMap> esimChip(Object reader, {bool cached = false}) => _map(
    'GET',
    cached ? '/api/esim/chip/cached' : '/api/esim/chip',
    query: _readerQuery(reader),
  );
  Future<JsonMap> esimProfiles(Object reader) =>
      _map('GET', '/api/esim/profiles', query: _readerQuery(reader));
  Future<JsonMap> esimEnable(String iccid, Object reader, [JsonMap? target]) =>
      _map(
        'POST',
        '/api/esim/profiles/${Uri.encodeComponent(iccid)}/enable',
        body: _readerBody(reader, target),
      );
  Future<JsonMap> esimDisable(String iccid, Object reader, [JsonMap? target]) =>
      _map(
        'POST',
        '/api/esim/profiles/${Uri.encodeComponent(iccid)}/disable',
        body: _readerBody(reader, target),
      );
  Future<JsonMap> esimDelete(String iccid, Object reader, [JsonMap? target]) =>
      _map(
        'DELETE',
        '/api/esim/profiles/${Uri.encodeComponent(iccid)}',
        query: {..._readerQuery(reader), ...?target},
      );
  Future<JsonMap> esimNickname(
    String iccid,
    String nickname,
    Object reader, [
    JsonMap? target,
  ]) => _map(
    'POST',
    '/api/esim/profiles/${Uri.encodeComponent(iccid)}/nickname',
    body: _readerBody(reader, {'nickname': nickname, ...?target}),
  );
  Future<JsonMap> esimDownload(JsonMap body) =>
      _map('POST', '/api/esim/download', body: body);
  Future<JsonMap> esimDownloadCancel(Object reader, [JsonMap? target]) => _map(
    'POST',
    '/api/esim/download/cancel',
    body: _readerBody(reader, target),
  );
  Future<JsonMap> esimDiscovery([JsonMap? body]) =>
      _map('POST', '/api/esim/discovery', body: body ?? {});
  Future<JsonMap> esimNotifications(Object reader) =>
      _map('GET', '/api/esim/notifications', query: _readerQuery(reader));
  Future<JsonMap> esimProcessNotifications(Object reader, {Object? sequence}) =>
      _map(
        'POST',
        '/api/esim/notifications/process',
        body: _readerBody(reader, {'seq': ?sequence}),
      );
  Future<JsonMap> esimRemoveNotification(
    Object sequence,
    Object reader, [
    JsonMap? target,
  ]) => _map(
    'DELETE',
    '/api/esim/notifications/$sequence',
    query: {..._readerQuery(reader), ...?target},
  );
}

extension on Uri {
  bool get isLoopback =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';
}
