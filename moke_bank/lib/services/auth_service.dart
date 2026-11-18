import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'request_id.dart';
import 'session_storage.dart';

typedef Json = Map<String, dynamic>;

class ApiError implements Exception {
  const ApiError(this.message, {this.status = 0, this.code = ''});
  final String message;
  final int status;
  final String code;

  @override
  String toString() => message;
}

final auth = AuthService();

class AuthService extends ChangeNotifier {
  static const _base = String.fromEnvironment(
    'BANKOS_API',
    defaultValue: 'https://bank-os.duckdns.org/api/v1',
  );
  static final banks = <String, String>{
    for (final entry in const String.fromEnvironment(
      'BANKOS_BANKS',
      defaultValue: 'demo-a=Banco Demo A,demo-b=Banco Demo B',
    ).split(','))
      if (entry.contains('='))
        entry.substring(0, entry.indexOf('=')).trim(): entry
            .substring(entry.indexOf('=') + 1)
            .trim(),
  };

  static const _storage = SessionStorage();
  Future<void> _storageWrites = Future.value();
  String? _token;
  DateTime? _expiresAt;
  Timer? _expiry;
  Json? user;
  String? bank;
  bool expired = false;

  String get bankName => banks[bank] ?? bank ?? '';
  String? get role => user?['role'] as String?;

  Future<void> restore() async {
    final saved = await _storage.read();
    if (saved == null) return;
    try {
      final session = jsonDecode(saved);
      if (session case {'token': final String token}) {
        final profile = session['user'];
        final tenant = session['bank'];
        final expiry = DateTime.tryParse('${session['expires_at']}');
        if (token.isNotEmpty &&
            profile is Json &&
            {'ADMIN', 'CLIENT'}.contains(profile['role']) &&
            tenant is String &&
            tenant.isNotEmpty &&
            expiry != null &&
            expiry.isAfter(DateTime.now())) {
          _setSession(token, profile, tenant, expiry);
          return;
        }
      }
    } on FormatException {
      // An unreadable stored session must be discarded.
    }
    await _clear(expired: true);
  }

  Future<void> _persist(String? session) =>
      _storageWrites = _storageWrites.then((_) => _storage.save(session));

  Future<void> login({
    required String tenantSlug,
    required String correo,
    required String contrasena,
  }) async {
    final data = await request(
      'POST',
      '/auth/login',
      authenticated: false,
      body: {
        'tenant_slug': tenantSlug,
        'email': correo.trim(),
        'password': contrasena,
      },
    ) as Json;
    final token = data['access_token'];
    final profile = data['user'];
    final seconds = data['expires_in'];
    if (token is! String ||
        token.isEmpty ||
        profile is! Json ||
        !{'ADMIN', 'CLIENT'}.contains(profile['role']) ||
        seconds is! int ||
        seconds <= 0) {
      throw const ApiError('La API devolvió una sesión inválida.');
    }
    final expiry = DateTime.now().toUtc().add(Duration(seconds: seconds));
    await _persist(
      jsonEncode({
        'token': token,
        'user': profile,
        'bank': tenantSlug,
        'expires_at': expiry.toIso8601String(),
      }),
    );
    _setSession(token, profile, tenantSlug, expiry);
  }

  void _setSession(String token, Json profile, String tenant, DateTime expiry) {
    _expiry?.cancel();
    _token = token;
    _expiresAt = expiry;
    user = profile;
    bank = tenant;
    expired = false;
    _expiry = Timer(expiry.difference(DateTime.now()), () {
      unawaited(_clear(expired: true));
    });
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await request('POST', '/auth/logout');
    } finally {
      await _clear();
    }
  }

  Future<void> _clear({bool expired = false}) {
    _expiry?.cancel();
    _token = null;
    _expiresAt = null;
    user = null;
    bank = null;
    this.expired = expired;
    final deletion = _persist(null);
    notifyListeners();
    return deletion;
  }

  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    Map<String, String> headers = const {},
    bool authenticated = true,
  }) async {
    if (authenticated && _expiresAt?.isAfter(DateTime.now()) == false) {
      await _clear(expired: true);
    }
    final token = authenticated ? _token : null;
    if (authenticated && token == null) {
      throw const ApiError('Vuelve a iniciar sesión.', status: 401);
    }
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final client = http.Client();
    try {
      final request = http.Request(method, uri);
      request.headers.addAll({
        'Accept': 'application/json',
        if (!headers.containsKey('X-Correlation-ID'))
          'X-Correlation-ID': newRequestId(),
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        ...headers,
      });
      if (body != null) request.body = jsonEncode(body);
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401 && token != null && token == _token) {
        await _clear(expired: true);
      }
      Json? envelope;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Json) envelope = decoded;
      } on FormatException {
        // Proxies can return an HTML error page.
      }
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          envelope?['success'] == true) {
        return envelope!['data'];
      }
      final retry = response.headers['retry-after'];
      final message = response.statusCode == 429 && retry != null
          ? 'Espera $retry segundos y vuelve a intentar.'
          : envelope?['message'] as String? ??
                'La API devolvió un error (${response.statusCode}).';
      throw ApiError(
        message,
        status: response.statusCode,
        code: envelope?['code'] as String? ?? '',
      );
    } on TimeoutException {
      throw const ApiError('La API tardó demasiado en responder.');
    } on http.ClientException {
      throw const ApiError('No se pudo conectar. Revisa tu conexión.');
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  Future<Json> get(String path, {Map<String, String>? query}) async =>
      await request('GET', path, query: query) as Json;

  Future<List<Json>> page(
    String path, {
    Map<String, String> filters = const {},
  }) async {
    final rows = <Json>[];
    for (var page = 1; ; page++) {
      final data = await get(
        path,
        query: {...filters, 'page': '$page', 'limit': '100'},
      );
      rows.addAll((data['items'] as List).cast<Json>());
      if (data['has_more'] != true) return rows;
    }
  }
}
