import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/bus_location.dart';

class ApiService {
  static String get baseUrl => _normalizeApiBase(AppConfig.apiBaseUrl);
  static String get trackingBaseUrl => baseUrl;
  static String get trackingLatestEndpoint => '$baseUrl/location/latest';
  static const Duration _telemetryEndpointBackoff = Duration(seconds: 45);
  static final Map<String, DateTime> _telemetryBackoffUntil = {};

  static String _normalizeApiBase(String rawBase) {
    var base = rawBase.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.endsWith('/api')) {
      base = '$base/api';
    }
    return base;
  }

  static Future<BusLocation?> fetchLatestLocation() async {
    final endpoint = '$baseUrl/location/latest';

    final now = DateTime.now();
    final backoffUntil = _telemetryBackoffUntil[endpoint];
    if (backoffUntil != null && now.isBefore(backoffUntil)) {
      return null;
    }

    try {
      final response = await http
          .get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 4));
      if (kDebugMode) {
        debugPrint('Telemetry GET $endpoint -> ${response.statusCode}');
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          _telemetryBackoffUntil.remove(endpoint);
          final payload = data['data'] is Map<String, dynamic>
              ? data['data'] as Map<String, dynamic>
              : data;
          final location = BusLocation.fromJson(payload);
          if (kDebugMode) {
            debugPrint(
              'Telemetry parsed from $endpoint: '
              'bus=${location.busId}, lat=${location.lat}, lng=${location.lng}, speed=${location.speed}',
            );
          }
          return location;
        }
      }

      _telemetryBackoffUntil[endpoint] = DateTime.now().add(
        _telemetryEndpointBackoff,
      );
    } catch (e) {
      _telemetryBackoffUntil[endpoint] = DateTime.now().add(
        _telemetryEndpointBackoff,
      );
      if (kDebugMode) {
        debugPrint('Telemetry fetch failed for $endpoint: $e');
      }
    }

    return null;
  }

  static Future<List<BusLocation>> getAllBusesLocations({String? token}) async {
    final buses = await ApiService().getBuses(token: token);
    return buses
        .whereType<Map<String, dynamic>>()
        .map(BusLocation.fromJson)
        .toList();
  }

  static Map<String, String> _headers([String? token]) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  static String _unexpectedServerResponseMessage() =>
      'Unexpected server response — please try again.';

  static void _debugPrintResponse(String method, Uri uri, http.Response response) {
    if (kDebugMode) {
      debugPrint(
        '$method $uri -> ${response.statusCode} ${response.headers['content-type'] ?? 'unknown'}',
      );
    }
  }

  static dynamic _decodeJsonResponse(http.Response response) {
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    final body = response.body.trim();
    if (contentType.isEmpty && body.isNotEmpty && !body.startsWith('{') && !body.startsWith('[')) {
      throw Exception(_unexpectedServerResponseMessage());
    }
    if (!contentType.contains('application/json') &&
        !contentType.contains('+json') &&
        !body.startsWith('{') &&
        !body.startsWith('[')) {
      throw Exception(_unexpectedServerResponseMessage());
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      throw Exception(_unexpectedServerResponseMessage());
    }
  }

  Future<void> logout(String token) async {
    await http
        .post(Uri.parse('$baseUrl/auth/logout'), headers: _headers(token))
        .timeout(const Duration(seconds: 8));
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    if (kDebugMode) debugPrint('Login request URL: $uri');
    try {
      final response = await http
          .post(
            uri,
            headers: _headers(),
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      _debugPrintResponse('POST', uri, response);
      final data = _decodeJsonResponse(response);
      if (response.statusCode == 200 && data is Map<String, dynamic>) return data;
      if (data is Map<String, dynamic>) {
        throw Exception(data['error'] ?? 'Invalid email or password');
      }
      throw Exception(_unexpectedServerResponseMessage());
    } catch (e) {
      if (e is TimeoutException || e is http.ClientException) {
        throw Exception(
          'Could not reach the sign-in server. Check your connection and try again.',
        );
      }
      rethrow;
    }
  }

  Future<String> forgotPassword(String email) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/forgot-password'),
          headers: _headers(),
          body: jsonEncode({'email': email.trim().toLowerCase()}),
        )
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return data['message']?.toString() ??
          'If this account exists, a default password has been set. Check your email format.';
    }
    throw Exception(
      data is Map<String, dynamic>
          ? data['error']?.toString() ?? 'Password reset failed'
          : 'Password reset failed',
    );
  }

  Future<void> changePassword(String token, String newPassword) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/change-password'),
          headers: _headers(token),
          body: jsonEncode({'newPassword': newPassword}),
        )
        .timeout(const Duration(seconds: 10));
    final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    if (response.statusCode == 200) return;
    throw Exception(
      data is Map<String, dynamic>
          ? data['error']?.toString() ?? 'Could not update password'
          : 'Could not update password',
    );
  }

  Future<Map<String, dynamic>> driverLogin(String phone, String pin) async {
    final uri = Uri.parse('$baseUrl/auth/driver-login');
    if (kDebugMode) debugPrint('Driver login request URL: $uri');
    try {
      final response = await http
          .post(
            uri,
            headers: _headers(),
            body: jsonEncode({'phone': phone, 'pin': pin}),
          )
          .timeout(const Duration(seconds: 60));
      _debugPrintResponse('POST', uri, response);
      final data = _decodeJsonResponse(response);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      final message = data is Map<String, dynamic> ? data['error'] : null;
      throw Exception(message ?? 'Driver login failed');
    } on TimeoutException {
      throw Exception(
        'Server is waking up. Please wait a moment and try again.',
      );
    } on http.ClientException {
      throw Exception(
        'Could not reach the server. It may be waking up; please try again shortly.',
      );
    }
  }

  Future<Map<String, dynamic>> getDriverCurrentUser(String token) async {
    final response = await http
        .get(Uri.parse('$baseUrl/auth/driver/me'), headers: _headers(token))
        .timeout(const Duration(seconds: 15));
    final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['user'] is Map<String, dynamic>) {
      return data['user'] as Map<String, dynamic>;
    }
    throw Exception(
      data is Map<String, dynamic>
          ? data['error'] ?? 'Driver session expired'
          : 'Driver session expired',
    );
  }

  Future<int> sendDriverLocation(Map<String, dynamic> fix, String token) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/location'),
          headers: _headers(token),
          body: jsonEncode(fix),
        )
        .timeout(const Duration(seconds: 8));
    return response.statusCode;
  }

  Stream<List<Map<String, dynamic>>> streamBusUpdates(String token) async* {
    var retrySeconds = 1;
    while (true) {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse('$baseUrl/buses/stream'))
          ..headers.addAll(_headers(token))
          ..headers['Accept'] = 'text/event-stream';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) {
          throw Exception('Bus stream returned ${response.statusCode}');
        }
        retrySeconds = 1;
        final eventLines = <String>[];
        await for (final line
            in response.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.startsWith('data:')) {
            eventLines.add(line.substring(5).trimLeft());
          } else if (line.isEmpty && eventLines.isNotEmpty) {
            final decoded = jsonDecode(eventLines.join('\n'));
            eventLines.clear();
            if (decoded is List) {
              yield decoded.whereType<Map<String, dynamic>>().toList();
            }
          }
        }
        await Future<void>.delayed(Duration(seconds: retrySeconds));
        if (retrySeconds < 15) {
          retrySeconds = retrySeconds * 2 > 15 ? 15 : retrySeconds * 2;
        }
      } catch (error) {
        if (kDebugMode) debugPrint('Bus stream reconnecting: $error');
        await Future<void>.delayed(Duration(seconds: retrySeconds));
        if (retrySeconds < 15) {
          retrySeconds = retrySeconds * 2 > 15 ? 15 : retrySeconds * 2;
        }
      } finally {
        client.close();
      }
    }
  }

  Future<Map<String, dynamic>> getCurrentUser(String token) async {
    final response = await http
        .get(Uri.parse('$baseUrl/me'), headers: _headers(token))
        .timeout(const Duration(seconds: 8));

    final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      final user = data['user'];
      if (user is Map<String, dynamic>) return user;
      throw Exception('Invalid user response');
    }

    final message = data is Map<String, dynamic>
        ? (data['error']?.toString() ?? 'Session invalid')
        : 'Session invalid';
    throw Exception(message);
  }

  Future<Map<String, dynamic>> getApiRoot() async {
    final response = await http
        .get(Uri.parse(baseUrl))
        .timeout(const Duration(seconds: 8));
    final data = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};
    if (response.statusCode == 200 && data is Map<String, dynamic>) return data;
    throw Exception(
      data is Map<String, dynamic>
          ? data['error'] ?? 'API unavailable'
          : 'API unavailable',
    );
  }

  Future<Map<String, dynamic>> getHealth() async {
    final response = await http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 8));
    final data = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};
    if (response.statusCode == 200 && data is Map<String, dynamic>) return data;
    throw Exception(
      data is Map<String, dynamic>
          ? data['error'] ?? 'Health check failed'
          : 'Health check failed',
    );
  }

  Future<List<dynamic>> getHostels() async {
    final response = await http
        .get(Uri.parse('$baseUrl/hostels'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final parsed = jsonDecode(response.body);
      if (parsed is List) return parsed;
      if (parsed is Map<String, dynamic>) {
        final data = parsed['data'];
        if (data is List) return data;
      }
    }
    throw Exception('Failed to load hostels');
  }

  Future<List<dynamic>> getTelemetryDiagnostics({
    String? busId,
    int limit = 50,
    String? token,
  }) async {
    final segments = <String>[];
    if (busId != null && busId.isNotEmpty) segments.add('bus_id=$busId');
    if (limit > 0) segments.add('limit=$limit');
    final url = segments.isEmpty
        ? '$baseUrl/telemetry/diagnostics'
        : '$baseUrl/telemetry/diagnostics?${segments.join('&')}';
    final response = await http
        .get(Uri.parse(url), headers: _headers(token))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final parsed = jsonDecode(response.body);
      if (parsed is List) return parsed;
      if (parsed is Map<String, dynamic>) {
        final data = parsed['data'];
        if (data is List) return data;
      }
    }
    throw Exception('Failed to load telemetry diagnostics');
  }

  Future<List<dynamic>> getTelemetryHistory({
    String? busId,
    String? token,
  }) async {
    final query = busId != null && busId.isNotEmpty ? '?bus_id=$busId' : '';
    final response = await http
        .get(
          Uri.parse('$baseUrl/telemetry/history$query'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final parsed = jsonDecode(response.body);
      if (parsed is List) return parsed;
      if (parsed is Map<String, dynamic>) {
        final data = parsed['data'];
        if (data is List) return data;
      }
    }
    throw Exception('Failed to load telemetry history');
  }

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
    String hostelId,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: _headers(),
            body: jsonEncode({
              'name': name,
              'email': email,
              'password': password,
              'hostelId': hostelId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) return data;
      throw Exception(data['error'] ?? 'Registration failed');
    } catch (e) {
      if (e is TimeoutException || e is http.ClientException) {
        throw Exception('Could not reach the registration server. Try again.');
      }
      rethrow;
    }
  }

  Future<List<dynamic>> getBuses({String? hostel, String? token}) async {
    if (token == null || token.isEmpty) {
      throw Exception('Not logged in. Sign in again to load buses.');
    }

    final query = hostel == null
        ? ''
        : '?hostel=${Uri.encodeQueryComponent(hostel)}';
    final endpoints = ['$baseUrl/buses$query', '$baseUrl/all-buses$query'];
    Object? lastError;
    var requestCount = 0;

    for (
      var endpointIndex = 0;
      endpointIndex < endpoints.length && requestCount < 3;
      endpointIndex++
    ) {
      final url = endpoints[endpointIndex];
      var endpointRetries = 0;
      var retryCurrentEndpoint = true;
      while (retryCurrentEndpoint && requestCount < 3) {
        requestCount++;
        retryCurrentEndpoint = false;
        final timeout = Duration(seconds: requestCount == 1 ? 60 : 15);
        http.Response response;
        try {
          response = await http
              .get(Uri.parse(url), headers: _headers(token))
              .timeout(timeout);
        } on TimeoutException {
          lastError = Exception(
            'Server request timed out after ${timeout.inSeconds}s',
          );
          if (kDebugMode) {
            debugPrint('Bus fetch timeout for $url (${timeout.inSeconds}s)');
          }
          if (endpointRetries == 0 && requestCount < 3) {
            endpointRetries++;
            await Future<void>.delayed(const Duration(seconds: 1));
            retryCurrentEndpoint = true;
            continue;
          }
          break;
        } on http.ClientException catch (error) {
          lastError = Exception('Network error: ${error.message}');
          if (kDebugMode) {
            debugPrint('Bus fetch network error for $url: ${error.message}');
          }
          if (endpointRetries == 0 && requestCount < 3) {
            endpointRetries++;
            await Future<void>.delayed(const Duration(seconds: 1));
            retryCurrentEndpoint = true;
            continue;
          }
          break;
        }

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final items = decoded is List
              ? decoded
              : decoded is Map<String, dynamic>
              ? decoded['data'] ?? decoded['buses']
              : null;
          if (items is List) return List<dynamic>.from(items);
          lastError = const FormatException('Unexpected buses response format');
          _logBusFetchFailure(url, response, lastError);
          break;
        }

        _logBusFetchFailure(url, response, 'HTTP ${response.statusCode}');
        final decoded = response.body.isEmpty
            ? null
            : _tryDecodeJson(response.body);
        final serverMessage = decoded is Map<String, dynamic>
            ? decoded['error']?.toString()
            : null;
        if (response.statusCode == 401) {
          throw Exception(
            serverMessage ?? 'Session expired. Please sign in again.',
          );
        }
        if (response.statusCode == 403) {
          throw Exception(
            serverMessage ?? 'You are not allowed to view these buses.',
          );
        }

        lastError = Exception(
          serverMessage ??
              'Bus request failed with HTTP ${response.statusCode}',
        );
        if (response.statusCode == 404 &&
            endpointIndex + 1 < endpoints.length) {
          break;
        }
        if (response.statusCode >= 500 &&
            endpointRetries == 0 &&
            requestCount < 3) {
          endpointRetries++;
          await Future<void>.delayed(const Duration(seconds: 1));
          retryCurrentEndpoint = true;
          continue;
        }
        break;
      }
    }

    throw Exception(
      lastError?.toString() ?? 'Could not load buses. Please retry.',
    );
  }

  static dynamic _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static void _logBusFetchFailure(
    String url,
    http.Response response,
    Object error,
  ) {
    if (!kDebugMode) return;
    final body = response.body.length > 600
        ? '${response.body.substring(0, 600)}…'
        : response.body;
    debugPrint(
      'Bus fetch failed: $url -> ${response.statusCode}; $error; body=$body',
    );
  }

  Future<Map<String, dynamic>?> getBus(int busNumber, {String? token}) async {
    final response = await http
        .get(Uri.parse('$baseUrl/buses/$busNumber'), headers: _headers(token))
        .timeout(const Duration(seconds: 8));
    final data = _tryDecodeJson(response.body);
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return data;
    }
    throw Exception(
      data is Map<String, dynamic>
          ? data['error']?.toString() ?? 'Could not load bus'
          : 'Could not load bus',
    );
  }

  Future<List<dynamic>> getTodayScheduledBuses({
    required String token,
    DateTime? date,
  }) async {
    final day = date ?? DateTime.now();
    final dateText =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final response = await http
        .get(
          Uri.parse('$baseUrl/today-buses?date=$dateText'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data is List) return data;
    throw Exception(
      data is Map<String, dynamic>
          ? data['error']?.toString() ?? 'Could not load today’s buses'
          : 'Could not load today’s buses',
    );
  }

  Future<List<dynamic>> getSchedules({
    String? hostel,
    String? date,
    String? token,
  }) async {
    final query = <String, String>{};
    if (date != null) query['date'] = date;
    if (hostel != null) query['hostel'] = hostel;
    final uri = Uri.parse('$baseUrl/schedules').replace(
      queryParameters: query.isEmpty ? null : query,
    );
    final response = await http
        .get(uri, headers: _headers(token))
        .timeout(const Duration(seconds: 8));
    final data = _tryDecodeJson(response.body);
    if (response.statusCode == 200 && data is List) return data;
    throw Exception(
      data is Map<String, dynamic>
          ? data['error']?.toString() ?? 'Could not load schedules'
          : 'Could not load schedules',
    );
  }

  Future<Map<String, dynamic>> updateSchedule(
    Map<String, dynamic> data,
    String token,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/schedules'),
          headers: _headers(token),
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 10));
    final body = _tryDecodeJson(response.body);
    if (response.statusCode == 200 && body is Map<String, dynamic>) {
      return body;
    }
    throw Exception(
      body is Map<String, dynamic>
          ? body['error']?.toString() ?? 'Could not update schedule'
          : 'Could not update schedule',
    );
  }

  Future<Map<String, dynamic>> updateBusStatus(
    int busNumber,
    String status,
    String token,
  ) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/buses/$busNumber'),
          headers: _headers(token),
          body: jsonEncode({'status': status}),
        )
        .timeout(const Duration(seconds: 10));

    final data = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};
    if (response.statusCode == 200) {
      return data is Map<String, dynamic>
          ? data
          : <String, dynamic>{'data': data};
    }

    throw Exception(
      data is Map<String, dynamic>
          ? data['error'] ?? 'Failed to update bus status'
          : 'Failed to update bus status',
    );
  }

  Future<Map<String, dynamic>> addBus({
    required int busNumber,
    required String assignedHostel,
    required String driverName,
    required String driverPhone,
    required String pin,
    required String token,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/buses'),
          headers: _headers(token),
          body: jsonEncode({
            'busNumber': busNumber,
            'assignedHostel': assignedHostel,
            'driverName': driverName,
            'driverPhone': driverPhone,
            'pin': pin,
          }),
        )
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    }

    throw Exception(
      data is Map<String, dynamic>
          ? data['error'] ?? 'Failed to add bus'
          : 'Failed to add bus',
    );
  }

  Future<Map<String, dynamic>> updateBusDriver({
    required int busNumber,
    required String driverName,
    required String driverPhone,
    required String token,
    String? pin,
  }) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/buses/$busNumber/driver'),
          headers: _headers(token),
          body: jsonEncode({
            'driverName': driverName,
            'driverPhone': driverPhone,
            if (pin != null && pin.isNotEmpty) 'pin': pin,
          }),
        )
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    }

    throw Exception(
      data is Map<String, dynamic>
          ? data['error'] ?? 'Failed to update driver'
          : 'Failed to update driver',
    );
  }

  Future<List<dynamic>> getNotifications({
    String? hostel,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl/notifications').replace(
      queryParameters: hostel == null ? null : {'hostel': hostel},
    );
    final response = await http
        .get(uri, headers: _headers(token))
        .timeout(const Duration(seconds: 8));
    final data = _tryDecodeJson(response.body);
    if (response.statusCode == 200 && data is List) return data;
    throw Exception(
      data is Map<String, dynamic>
          ? data['error']?.toString() ?? 'Could not load notifications'
          : 'Could not load notifications',
    );
  }

  Future<Map<String, dynamic>> sendNotification(
    Map<String, dynamic> data,
    String token,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/notifications/send'),
          headers: _headers(token),
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 10));
    final body = _tryDecodeJson(response.body);
    if (response.statusCode == 200 && body is Map<String, dynamic>) {
      return body;
    }
    throw Exception(
      body is Map<String, dynamic>
          ? body['error']?.toString() ?? 'Could not send notification'
          : 'Could not send notification',
    );
  }

  // ============ DEMO DATA ============
  List<Map<String, dynamic>> _getDemoBuses(String? hostelFilter) {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final allBuses = [
      _bus(
        1,
        'GH1',
        'Pa Hlutea',
        '9436168711',
        23.7285,
        92.7180,
        'idle',
        today,
        '8:30 AM',
        '1:30 PM',
      ),
      _bus(
        2,
        'GH1',
        'Pu Stephen',
        '8787778119',
        23.7260,
        92.7165,
        'running',
        today,
        '9:15 AM',
        '4:30 PM',
      ),
      _bus(
        3,
        'GH1',
        'Mawizuala',
        '8131811729',
        23.7290,
        92.7200,
        'idle',
        today,
        '8:30 AM',
        '5:30 PM',
      ),
      _bus(
        4,
        'GH2',
        'Hruaia',
        '6909101103',
        23.7240,
        92.7150,
        'running',
        today,
        '8:15 AM',
        '4:30 PM',
      ),
      _bus(
        5,
        'BH1',
        'Chhuanga',
        '9862369186',
        23.7275,
        92.7185,
        'running',
        today,
        '8:15 AM',
        '5:30 PM',
      ),
      _bus(
        6,
        'BH1',
        'Pa Dina',
        '9615408299',
        23.7265,
        92.7170,
        'idle',
        today,
        '8:15 AM',
        '7:00 PM',
      ),
      _bus(
        7,
        'BH1',
        'Vk-a',
        '7005367693',
        23.7280,
        92.7195,
        'running',
        today,
        '8:15 PM',
        '5:30 PM',
      ),
      _bus(
        8,
        'BH1',
        'Dama',
        '7005364878',
        23.7255,
        92.7160,
        'idle',
        today,
        '6:30 AM',
        '12:30 PM',
        note: 'IoN Digital Centre Mualpui',
      ),
      _bus(
        9,
        'BH1',
        'Mala',
        '6009425695',
        23.7295,
        92.7205,
        'maintenance',
        today,
        '1:00 PM',
        '4:30 PM',
      ),
      _bus(
        10,
        'BH1',
        'Rinkima',
        '7005616947',
        23.7270,
        92.7175,
        'idle',
        today,
        '9:15 AM',
        '1:30 PM',
      ),
      _bus(
        11,
        'BH1',
        'Pa Dika',
        '6909470121',
        23.7250,
        92.7155,
        'running',
        today,
        '9:15 AM',
        '1:30 PM',
      ),
      _bus(
        12,
        'BH1',
        'Ramtea',
        '8729985255',
        23.7285,
        92.7190,
        'idle',
        today,
        '10:15 AM',
        '2:30 PM',
      ),
      _bus(
        13,
        'BH2',
        'Lalrammawia',
        '9862411234',
        23.7260,
        92.7165,
        'running',
        today,
        '9:20 AM',
        '2:00 PM',
      ),
      _bus(
        14,
        'BH2',
        'Vanlalruata',
        '8014567890',
        23.7245,
        92.7148,
        'idle',
        today,
        '8:20 AM',
        '3:20 PM',
      ),
      _bus(
        15,
        'BH2',
        'Zohmingliana',
        '7005223344',
        23.7300,
        92.7210,
        'running',
        today,
        '8:20 AM',
        '11:15 AM',
      ),
      _bus(
        16,
        'BH3',
        'Lalduhawma',
        '9856112233',
        23.7230,
        92.7140,
        'idle',
        today,
        '8:00 AM',
        '4:00 PM',
      ),
      _bus(
        17,
        'BH3',
        'Vanlalngaia',
        '6009334455',
        23.7315,
        92.7215,
        'running',
        today,
        '9:00 AM',
        '5:00 PM',
      ),
      _bus(
        18,
        'BH3',
        'Hmingthansanga',
        '7005556677',
        23.7240,
        92.7155,
        'idle',
        today,
        '8:30 AM',
        '3:30 PM',
      ),
      _bus(
        19,
        'BH3',
        'Lalremruata',
        '8259667788',
        23.7305,
        92.7205,
        'idle',
        today,
        '9:30 AM',
        '4:30 PM',
      ),
      _bus(
        20,
        'BH3',
        'Thangmawia',
        '9612778899',
        23.7235,
        92.7145,
        'running',
        today,
        '10:00 AM',
        '2:00 PM',
      ),
      _bus(
        21,
        'BH4',
        'Kaptluanga',
        '9862990011',
        23.7320,
        92.7220,
        'idle',
        today,
        '8:45 AM',
        '5:00 PM',
      ),
      _bus(
        22,
        'GH2',
        'Saka',
        '9378074359',
        23.7245,
        92.7152,
        'running',
        today,
        '8:25 AM',
        '5:30 PM',
      ),
    ];
    if (hostelFilter != null) {
      return allBuses
          .where((b) => b['assignedHostel'] == hostelFilter)
          .toList();
    }
    return allBuses;
  }

  Map<String, dynamic> _bus(
    int num,
    String hostel,
    String driver,
    String phone,
    double lat,
    double lng,
    String status,
    String date,
    String fromHostel,
    String fromMBSE, {
    String note = '',
  }) {
    return {
      'busNumber': num,
      'assignedHostel': hostel,
      'status': status,
      'latitude': lat,
      'longitude': lng,
      'speed': status == 'running' ? 25.0 : 0.0,
      'isEnabled': true,
      'route': 'Hostel ↔ MBSE',
      'driver': {
        '_id': 'drv$num',
        'name': driver,
        'phone': phone,
        'busNumber': num,
        'isActive': true,
      },
      'schedule': {
        '_id': 'sch$num',
        'busNumber': num,
        'date': date,
        'fromHostelTime': fromHostel,
        'fromMBSETime': fromMBSE,
        'specialNote': note,
        'updatedBy': 'admin@nitmz.ac.in',
      },
    };
  }

  List<Map<String, dynamic>> _getDemoSchedules(String? hostelFilter) {
    return _getDemoBuses(
      hostelFilter,
    ).map((b) => b['schedule'] as Map<String, dynamic>).toList();
  }

  List<Map<String, dynamic>> _getDemoNotifications() {
    return [
      {
        '_id': 'n1',
        'title': 'Bus 5 Departure Alert',
        'message': 'Bus 5 will depart from BH1 at 8:15 AM. Please be ready!',
        'type': 'departure',
        'busNumber': 5,
        'targetHostel': 'BH1',
        'sentAt': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
        'isRead': false,
      },
      {
        '_id': 'n2',
        'title': 'Bus 7 Schedule Update',
        'message':
            'Bus 7 schedule updated. From Hostel: 8:15 PM, From MBSE: 5:30 PM',
        'type': 'general',
        'busNumber': 7,
        'targetHostel': 'BH1',
        'sentAt': DateTime.now()
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
        'isRead': false,
      },
      {
        '_id': 'n3',
        'title': 'Bus 2 Arriving Soon',
        'message': 'Bus 2 (GH1) is 1 km away from hostel. ETA: 5 minutes!',
        'type': 'arrival',
        'busNumber': 2,
        'targetHostel': 'GH1',
        'sentAt': DateTime.now()
            .subtract(const Duration(hours: 3))
            .toIso8601String(),
        'isRead': true,
      },
      {
        '_id': 'n4',
        'title': 'Bus 9 Maintenance',
        'message':
            'Bus 9 is under maintenance today. Please use alternate buses.',
        'type': 'delay',
        'busNumber': 9,
        'targetHostel': 'BH1',
        'sentAt': DateTime.now()
            .subtract(const Duration(hours: 5))
            .toIso8601String(),
        'isRead': true,
      },
    ];
  }
}
