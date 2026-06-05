import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'telemetry/device.dart';

const _refreshBufferSeconds = 300;
const _maxRetries = 2;
const _retryDelayMs = 1000;
const _defaultBase = 'https://mobileai.cloud';

class _SessionState {
  final String token;
  final int expiresAt;
  Timer? refreshTimer;

  _SessionState({
    required this.token,
    required this.expiresAt,
  });
}

_SessionState? _session;
Future<String>? _exchangePromise;

String _resolveBaseUrl(String? baseUrl) {
  if (baseUrl != null && baseUrl.isNotEmpty) return baseUrl.replaceAll(RegExp(r'/$'), '');
  return _defaultBase;
}

bool _isExpired() {
  return _session == null || DateTime.now().millisecondsSinceEpoch >= _session!.expiresAt;
}

bool _isNearExpiry() {
  if (_session == null) return true;
  return DateTime.now().millisecondsSinceEpoch >=
      _session!.expiresAt - _refreshBufferSeconds * 1000;
}

Future<Map<String, dynamic>> _fetchSession(
  String analyticsKey,
  String deviceId,
  String baseUrl, [
  int attempt = 0,
]) async {
  final url = Uri.parse('$baseUrl/api/v1/proxy-session');
  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'analyticsKey': analyticsKey, 'deviceId': deviceId}),
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    if (attempt < _maxRetries && response.statusCode >= 500) {
      await Future.delayed(Duration(milliseconds: _retryDelayMs * (attempt + 1)));
      return _fetchSession(analyticsKey, deviceId, baseUrl, attempt + 1);
    }

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}

    throw Exception(
      body['code'] as String? ?? 'proxy_session_exchange_failed_${response.statusCode}',
    );
  }

  return jsonDecode(response.body) as Map<String, dynamic>;
}

void _scheduleRefresh(String analyticsKey, String? baseUrl) {
  if (_session == null) return;

  _session!.refreshTimer?.cancel();

  final msUntilRefresh = (_session!.expiresAt -
          DateTime.now().millisecondsSinceEpoch -
          _refreshBufferSeconds * 1000)
      .clamp(1000, double.infinity)
      .toInt();

  _session!.refreshTimer = Timer(Duration(milliseconds: msUntilRefresh), () {
    exchangeToken(analyticsKey, baseUrl: baseUrl).catchError((e) {
      // Background refresh failed — will retry on next getSessionToken call
      return '';
    });
  });
}

Future<String> exchangeToken(String analyticsKey, {String? baseUrl}) {
  if (_exchangePromise != null) return _exchangePromise!;

  _exchangePromise = () async {
    try {
      final deviceId = getDeviceId() ?? await initDeviceId();
      final resolvedBase = _resolveBaseUrl(baseUrl);
      final result = await _fetchSession(analyticsKey, deviceId, resolvedBase);
      final now = DateTime.now().millisecondsSinceEpoch;

      _session?.refreshTimer?.cancel();

      _session = _SessionState(
        token: result['token'] as String,
        expiresAt: now + ((result['expiresIn'] as int) * 1000),
      );

      _scheduleRefresh(analyticsKey, baseUrl);
      return result['token'] as String;
    } finally {
      _exchangePromise = null;
    }
  }();

  return _exchangePromise!;
}

Future<String> getSessionToken(String analyticsKey, {String? baseUrl}) async {
  if (_session != null && !_isExpired()) {
    if (_isNearExpiry()) {
      unawaited(exchangeToken(analyticsKey, baseUrl: baseUrl).catchError((_) => ''));
    }
    return _session!.token;
  }

  return exchangeToken(analyticsKey, baseUrl: baseUrl);
}

String? getSessionTokenSync() {
  if (_session != null && !_isExpired()) return _session!.token;
  return null;
}

void clearSession() {
  _session?.refreshTimer?.cancel();
  _session = null;
  _exchangePromise = null;
}
