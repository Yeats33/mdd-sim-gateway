import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/gateway_api.dart';

class GatewayState extends ChangeNotifier {
  GatewayState({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _baseUriKey = 'gateway.base_uri';
  static const _certificateKey = 'gateway.certificate_sha256';
  static const _usernameKey = 'gateway.username';
  static const _sessionCookieKey = 'gateway.session_cookie';

  final FlutterSecureStorage _secureStorage;
  GatewayApi? _api;
  int _eventGeneration = 0;
  Timer? _refreshTimer;

  bool initialized = false;
  bool connecting = false;
  bool refreshing = false;
  bool configured = false;
  bool authenticated = false;
  String? error;
  String? username;
  Uri? endpoint;
  String? certificateSha256;
  JsonMap system = {};
  JsonMap update = {};
  JsonMap settings = {};
  JsonMap keepalive = {};
  List<JsonMap> devices = [];
  List<JsonMap> instances = [];
  List<JsonMap> cards = [];
  JsonMap? lastEvent;

  GatewayApi get api {
    final value = _api;
    if (value == null) {
      throw const GatewayApiException('尚未连接网关。');
    }
    return value;
  }

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final rawUri = preferences.getString(_baseUriKey);
    username = preferences.getString(_usernameKey);
    certificateSha256 = preferences.getString(_certificateKey);
    if (rawUri != null) {
      endpoint = Uri.tryParse(rawUri);
      if (endpoint != null) {
        _api = GatewayApi(
          baseUri: endpoint!,
          trustedCertificateSha256: certificateSha256,
          sessionCookie: await _secureStorage.read(key: _sessionCookieKey),
        );
        await _restoreAuthentication();
      }
    }
    initialized = true;
    notifyListeners();
  }

  Future<String?> inspectEndpoint(String raw) async {
    final uri = _parseEndpoint(raw);
    connecting = true;
    error = null;
    notifyListeners();
    try {
      return await GatewayApi.inspectCertificate(uri);
    } on Object catch (caught) {
      error = caught.toString();
      rethrow;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> configureEndpoint(String raw, {String? fingerprint}) async {
    final uri = _parseEndpoint(raw);
    connecting = true;
    error = null;
    notifyListeners();
    try {
      final candidate = GatewayApi(
        baseUri: uri,
        trustedCertificateSha256: fingerprint,
      );
      final status = await candidate.authStatus();
      endpoint = uri;
      certificateSha256 = fingerprint;
      _api = candidate;
      configured = status['configured'] == true;
      authenticated = status['authenticated'] == true;
      candidate.csrfToken = status['csrf']?.toString();
      username = status['username']?.toString() ?? username;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_baseUriKey, uri.toString());
      if (fingerprint == null) {
        await preferences.remove(_certificateKey);
      } else {
        await preferences.setString(_certificateKey, fingerprint);
      }
      await _persistSession();
      if (authenticated) await _onAuthenticated();
    } on Object catch (caught) {
      error = caught.toString();
      rethrow;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _stopLiveUpdates();
    _api = null;
    endpoint = null;
    certificateSha256 = null;
    configured = false;
    authenticated = false;
    username = null;
    clearSnapshot();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_baseUriKey);
    await preferences.remove(_certificateKey);
    await preferences.remove(_usernameKey);
    await _secureStorage.delete(key: _sessionCookieKey);
    notifyListeners();
  }

  Future<void> setup(
    String user,
    String password, {
    bool remember = true,
  }) async {
    await _authenticate(() => api.authSetup(user, password, remember), user);
  }

  Future<void> login(
    String user,
    String password, {
    bool remember = true,
  }) async {
    await _authenticate(() => api.authLogin(user, password, remember), user);
  }

  Future<void> _authenticate(
    Future<JsonMap> Function() operation,
    String user,
  ) async {
    connecting = true;
    error = null;
    notifyListeners();
    try {
      final result = await operation();
      api.csrfToken = result['csrf']?.toString();
      configured = true;
      authenticated = result['authenticated'] == true;
      username = user;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_usernameKey, user);
      await _persistSession();
      if (authenticated) await _onAuthenticated();
    } on Object catch (caught) {
      error = caught.toString();
      rethrow;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await api.authLogout();
    } finally {
      _stopLiveUpdates();
      api.csrfToken = null;
      api.sessionCookie = null;
      authenticated = false;
      await _secureStorage.delete(key: _sessionCookieKey);
      clearSnapshot();
      notifyListeners();
    }
  }

  Future<void> _restoreAuthentication() async {
    try {
      final status = await api.authStatus();
      configured = status['configured'] == true;
      authenticated = status['authenticated'] == true;
      api.csrfToken = status['csrf']?.toString();
      username = status['username']?.toString() ?? username;
      if (authenticated) await _onAuthenticated();
    } on Object catch (caught) {
      error = caught.toString();
      authenticated = false;
    }
  }

  Future<void> _onAuthenticated() async {
    await _persistSession();
    await refresh();
    _startLiveUpdates();
  }

  Future<void> _persistSession() async {
    final cookie = _api?.sessionCookie;
    if (cookie == null) {
      await _secureStorage.delete(key: _sessionCookieKey);
    } else {
      await _secureStorage.write(key: _sessionCookieKey, value: cookie);
    }
  }

  Future<void> refresh() async {
    if (!authenticated || refreshing) return;
    refreshing = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([
        _capture(api.devices),
        _capture(api.instances),
        _capture(api.cards),
        _capture(api.systemStatus),
        _capture(api.checkUpdate),
        _capture(api.settings),
        _capture(api.keepaliveSummary),
      ]);
      final deviceResult = results[0];
      if (deviceResult is JsonMap) devices = _list(deviceResult, 'devices');
      final instanceResult = results[1];
      if (instanceResult is JsonMap) {
        instances = _list(instanceResult, 'instances');
      }
      final cardResult = results[2];
      if (cardResult is JsonMap) cards = _list(cardResult, 'cards');
      final systemResult = results[3];
      if (systemResult is JsonMap) system = systemResult;
      final updateResult = results[4];
      if (updateResult is JsonMap) update = updateResult;
      final settingsResult = results[5];
      if (settingsResult is JsonMap) settings = settingsResult;
      final keepaliveResult = results[6];
      if (keepaliveResult is JsonMap) keepalive = keepaliveResult;
    } on GatewayApiException catch (caught) {
      error = caught.message;
      if (caught.status == 401) await _expireAuthentication();
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<T> mutate<T>(Future<T> Function(GatewayApi api) operation) async {
    error = null;
    notifyListeners();
    try {
      final result = await operation(api);
      await _persistSession();
      await refresh();
      return result;
    } on GatewayApiException catch (caught) {
      error = caught.message;
      if (caught.status == 401) await _expireAuthentication();
      notifyListeners();
      rethrow;
    }
  }

  Future<Object?> _capture(Future<JsonMap> Function() operation) async {
    try {
      return await operation();
    } on GatewayApiException catch (caught) {
      if (caught.status == 401) rethrow;
      return caught;
    }
  }

  List<JsonMap> _list(JsonMap response, String key) {
    final raw = response[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  void _startLiveUpdates() {
    _stopLiveUpdates();
    final generation = _eventGeneration;
    unawaited(_eventLoop(generation));
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(refresh()),
    );
  }

  void _stopLiveUpdates() {
    _eventGeneration += 1;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _eventLoop(int generation) async {
    while (authenticated && generation == _eventGeneration) {
      try {
        await for (final event in api.events()) {
          if (generation != _eventGeneration) return;
          lastEvent = event;
          _applyEvent(event);
          notifyListeners();
        }
      } on GatewayApiException catch (caught) {
        if (caught.status == 401) {
          await _expireAuthentication();
          return;
        }
      } on Object {
        // The periodic snapshot remains authoritative while the socket reconnects.
      }
      if (authenticated && generation == _eventGeneration) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  void _applyEvent(JsonMap event) {
    switch (event['type']) {
      case 'status':
        final id = event['instance']?.toString();
        instances = [
          for (final instance in instances)
            if (instance['id']?.toString() == id)
              {
                ...instance,
                'status': Map<String, dynamic>.from(event)
                  ..remove('type')
                  ..remove('instance'),
              }
            else
              instance,
        ];
      case 'cards':
        final raw = event['cards'];
        if (raw is List) {
          cards = raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      case 'device':
      case 'capability':
      case 'cellular':
      case 'engine':
        unawaited(refresh());
    }
  }

  Future<void> _expireAuthentication() async {
    _stopLiveUpdates();
    authenticated = false;
    api.csrfToken = null;
    api.sessionCookie = null;
    await _secureStorage.delete(key: _sessionCookieKey);
    clearSnapshot();
    notifyListeners();
  }

  void clearSnapshot() {
    devices = [];
    instances = [];
    cards = [];
    system = {};
    update = {};
    settings = {};
    keepalive = {};
    lastEvent = null;
  }

  static Uri _parseEndpoint(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const GatewayApiException('请输入 Mac 网关地址。');
    }
    return Uri.parse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
  }

  @override
  void dispose() {
    _stopLiveUpdates();
    super.dispose();
  }
}
