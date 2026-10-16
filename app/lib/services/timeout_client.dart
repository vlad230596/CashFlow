import 'dart:async';

import 'package:http/http.dart' as http;

/// Bounds how long a request may wait on an unreliable network.
///
/// [responseTimeout] covers DNS, connect, TLS and waiting for the response
/// headers; [bodyTimeout] then bounds downloading the body.
class TimeoutClient extends http.BaseClient {
  TimeoutClient(
    this._inner, {
    this.responseTimeout = const Duration(seconds: 15),
    this.bodyTimeout = const Duration(seconds: 30),
    this.onFinished,
  });

  final http.Client _inner;
  final Duration responseTimeout;
  final Duration bodyTimeout;

  /// Reports every request once its body has arrived or it failed; the status
  /// is known when only the body failed.
  final void Function(http.BaseRequest request, int? statusCode,
      Duration elapsed, Object? error)? onFinished;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch()..start();
    http.StreamedResponse? response;
    final List<int> body;
    try {
      response = await _inner.send(request).timeout(
            responseTimeout,
            onTimeout: () => throw TimeoutException(
              '${request.method} ${request.url.path} had no response',
              responseTimeout,
            ),
          );
      // Every caller reads whole JSON bodies, so buffering here costs nothing
      // and turns a stalled transfer into an ordinary failed request.
      body = await response.stream.toBytes().timeout(
            bodyTimeout,
            onTimeout: () => throw TimeoutException(
              '${request.method} ${request.url.path} body stalled',
              bodyTimeout,
            ),
          );
    } catch (error) {
      onFinished?.call(request, response?.statusCode, stopwatch.elapsed, error);
      rethrow;
    }
    onFinished?.call(request, response.statusCode, stopwatch.elapsed, null);
    return http.StreamedResponse(
      Stream.value(body),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
