import 'package:http/http.dart' as http;

class AuthenticatedApiClient extends http.BaseClient {
  AuthenticatedApiClient(
    this._inner,
    this._token,
    this._onUnauthorized,
    this._onSessionExpiration,
  );

  final http.Client _inner;
  final String? Function() _token;
  final Future<void> Function(String? token) _onUnauthorized;
  final Future<void> Function(String? token, String expiresAt)
      _onSessionExpiration;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = _token();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final response = await _inner.send(request);
    if (token != _token()) {
      throw StateError('The API request belongs to an older session');
    }
    if (response.statusCode == 401) {
      await _onUnauthorized(token);
    } else {
      final expiresAt = response.headers.entries
          .where(
            (header) =>
                header.key.toLowerCase() == 'x-cashflow-session-expires-at',
          )
          .map((header) => header.value)
          .firstOrNull;
      if (expiresAt != null) {
        await _onSessionExpiration(token, expiresAt);
      }
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

class ApiException implements Exception {
  const ApiException(this.endpoint, this.statusCode, this.message);
  final String endpoint;
  final int statusCode;
  final String message;
  @override
  String toString() => '$message ($endpoint, HTTP $statusCode)';
}
