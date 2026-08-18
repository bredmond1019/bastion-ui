// Widget tests for the run-control row on `_RunDetailBody` (`BU.12.D`
// task 6).
//
// `_RunControlRow`/`_RunDetailBody` are private to `runs_screen.dart`, so
// (like `runs_screen_test.dart` and `runs_reachable_test.dart`) this file
// drives them through the real, public `RunsScreen` — tap a run row, land
// on the detail body, exercise the control row that lives there.
//
// `RunsScreen` builds its own `EngineApi` internally (`_RunDetailBody`
// `._initEngine`) with no transport-injection seam, unlike `BastionApi`
// (which IS overridden via `bastionApiProvider` + `FakeHttpTransport`, as
// in `runs_screen_test.dart`). `EngineApi` always falls back to the
// production `IoHttpTransport`, so the only seam available to a widget
// test is `dart:io`'s process-wide `HttpOverrides` — the same technique
// `settings_engine_key_test.dart` uses for `EngineApi`'s mount probe. That
// file's fake responds with one fixed status for every request; the
// control row's tests need to distinguish the mount probe
// (`GET /workflows`) from `pause`/`resume`/`abort` calls to different run
// ids, so `_RoutingFakeHttpClient` below generalizes it into a
// method+path router (mirroring `FakeHttpTransport`'s `.on()` shape, but
// at the raw `dart:io` `HttpClient` layer `EngineApi` actually uses).
//
// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/runs_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart'
    show secureStorageProvider;
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'package:bastion_ui/theme/app_theme.dart';

import '../support/fake_http_transport.dart';

const _kHostKey = 'bastion.server.host';
const _kPortKey = 'bastion.server.port';
const _kEngineKeyKey = 'bastion.auth.engine_key';

const _sentinelKey = 'sentinel-run-control-do-not-leak-77ab';

// ---------------------------------------------------------------------------
// Fake FlutterSecureStorage (mirrors settings_engine_key_test.dart)
// ---------------------------------------------------------------------------

class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String?> store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }
}

_FakeSecureStorage _storageWith({String? engineKey}) {
  final storage = _FakeSecureStorage();
  storage.store[_kHostKey] = 'engine-test-host';
  storage.store[_kPortKey] = '4317';
  if (engineKey != null) {
    storage.store[_kEngineKeyKey] = engineKey;
  }
  return storage;
}

// ---------------------------------------------------------------------------
// A method+path ROUTING fabricated HttpClient — generalizes
// settings_engine_key_test.dart's single-fixed-response fake so pause,
// resume, abort and the mount probe can each return their own canned
// response by (method, path), never touching a real socket.
// ---------------------------------------------------------------------------

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, String> captured = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    captured[name] = value.toString();
  }

  @override
  List<String>? operator [](String name) =>
      captured.containsKey(name) ? <String>[captured[name]!] : null;
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  late bool chunkedTransferEncoding;
  @override
  void clear() {}
  @override
  int contentLength = -1;
  @override
  ContentType? contentType;
  @override
  DateTime? date;
  @override
  DateTime? expires;
  @override
  void forEach(void Function(String name, List<String> values) f) {}
  @override
  String? host;
  @override
  DateTime? ifModifiedSince;
  @override
  void noFolding(String name) {}
  @override
  late bool persistentConnection;
  @override
  int? port;
  @override
  void remove(String name, Object value) {}
  @override
  void removeAll(String name) {}
  @override
  String? value(String name) => captured[name];
}

class _FakeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpResponse(this.statusCode, String body)
    : _bytes = Uint8List.fromList(utf8.encode(body));

  final Uint8List _bytes;

  @override
  final int statusCode;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  int get contentLength => _bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  List<Cookie> get cookies => <Cookie>[];
  @override
  Future<Socket> detachSocket() =>
      Future<Socket>.error(UnsupportedError('Fake response'));
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => '';
  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) => Future<HttpClientResponse>.error(UnsupportedError('Fake response'));
  @override
  List<RedirectInfo> get redirects => <RedirectInfo>[];
}

/// One registered `(method, path)` response, consumed once per matching
/// request (the final registered response for a route repeats once its
/// queue is exhausted, mirroring [FakeHttpTransport]).
class _RoutedResponse {
  const _RoutedResponse(this.status, this.body);
  final int status;
  final String body;
}

class _RecordedCall {
  _RecordedCall(this.method, this.path, this.headers);
  final String method;
  final String path;
  final Map<String, String> headers;
}

class _RoutingFakeHttpClient implements HttpClient {
  final Map<String, List<_RoutedResponse>> _routes = {};
  final List<_RecordedCall> calls = [];

  void on(
    String method,
    String path, {
    required int status,
    required Object body,
  }) {
    final encoded = body is String ? body : jsonEncode(body);
    final key = '${method.toUpperCase()} $path';
    _routes.putIfAbsent(key, () => []).add(_RoutedResponse(status, encoded));
  }

  int callCount(String method, String path) => calls
      .where((c) => c.method == method.toUpperCase() && c.path == path)
      .length;

  Future<HttpClientResponse> _resolve(
    String method,
    String path,
    _FakeHttpHeaders headers,
  ) async {
    final key = '${method.toUpperCase()} $path';
    final list = _routes[key];
    if (list == null || list.isEmpty) {
      throw StateError(
        'Unregistered fake route: $key '
        '(registered: ${_routes.keys.join(', ')})',
      );
    }
    final resp = list.length > 1 ? list.removeAt(0) : list.first;
    calls.add(_RecordedCall(method.toUpperCase(), path, headers.captured));
    return _FakeHttpResponse(resp.status, resp.body);
  }

  Future<HttpClientRequest> _request(String method, Uri url) async =>
      _FakeHttpRequest(client: this, method: method, path: url.path);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _request('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _request('POST', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _request('DELETE', url);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _request('GET', Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _request('POST', Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _request(
        'DELETE',
        Uri(scheme: 'http', host: host, port: port, path: path),
      );

  @override
  void close({bool force = false}) {}

  // Unused by IoHttpTransport — never exercised, but required by the
  // interface.
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;
  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {}
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) {}
  @override
  Future<ConnectionTask<Socket>> Function(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  )?
  connectionFactory;
  @override
  Future<bool> Function(Uri url, String scheme, String realm)? authenticate;
  @override
  Future<bool> Function(String host, int port, String scheme, String realm)?
  authenticateProxy;
  @override
  bool Function(X509Certificate cert, String host, int port)?
  badCertificateCallback;
  @override
  void Function(String line)? keyLog;
  @override
  String Function(Uri url)? findProxy;
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      throw UnsupportedError('unused');
  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      throw UnsupportedError('unused');
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => throw UnsupportedError('unused');
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      throw UnsupportedError('unused');
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      throw UnsupportedError('unused');
  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      throw UnsupportedError('unused');
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      throw UnsupportedError('unused');
  @override
  Future<HttpClientRequest> putUrl(Uri url) => throw UnsupportedError('unused');
}

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest({
    required this.client,
    required this.method,
    required this.path,
  });

  final _RoutingFakeHttpClient client;
  @override
  final String method;
  final String path;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  bool bufferOutput = true;
  @override
  int contentLength = -1;
  @override
  late Encoding encoding;
  @override
  bool followRedirects = true;
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) => Future<void>.value();
  @override
  Future<HttpClientResponse> close() =>
      client._resolve(method, path, headers as _FakeHttpHeaders);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  List<Cookie> get cookies => <Cookie>[];
  @override
  Future<HttpClientResponse> get done => close();
  @override
  Future<void> flush() => Future<void>.value();
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  Uri get uri => Uri();
  @override
  void write(Object? obj) {}
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? obj = '']) {}
}

class _RoutingFakeHttpOverrides extends HttpOverrides {
  _RoutingFakeHttpOverrides(this.client);
  final _RoutingFakeHttpClient client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

/// Installs [client] as the process-wide [HttpOverrides] for one test,
/// restoring whatever was there before in `tearDown` (mirrors
/// `settings_engine_key_test.dart`'s `_installFakeHttp`).
_RoutingFakeHttpClient _installRoutingHttp(WidgetTester tester) {
  final client = _RoutingFakeHttpClient();
  final previous = HttpOverrides.current;
  HttpOverrides.global = _RoutingFakeHttpOverrides(client);
  addTearDown(() => HttpOverrides.global = previous);
  return client;
}

// ---------------------------------------------------------------------------
// WS fake + harness (mirrors runs_screen_test.dart)
// ---------------------------------------------------------------------------

class _FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();

  @override
  Future<void> get ready => _readyCompleter.future;
  @override
  Stream<dynamic> get messageStream => _controller.stream;
  @override
  void send(String data) {}
  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }
}

Future<void> pump(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<Widget> _buildHarness({
  required FakeHttpTransport httpTransport,
  required FlutterSecureStorage storage,
}) async {
  final wsTransport = _FakeWsTransport();
  final socket = BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transportFactory: (uri, {headers}) => wsTransport,
  );
  socket.connect();
  wsTransport.completeReady();

  final api = BastionApi(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transport: httpTransport,
  );

  return ProviderScope(
    overrides: [
      bastionSocketProvider.overrideWith((ref) => socket),
      bastionApiProvider.overrideWith((ref) => api),
      secureStorageProvider.overrideWithValue(storage),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: const RunsScreen()),
  );
}

/// Seeds `GET /api/runs` with one run + `GET /api/runs/<id>` with an empty
/// node list, pumps the harness, then taps into the run's detail body.
Future<void> _openDetail(
  WidgetTester tester, {
  required FakeHttpTransport http,
  required FlutterSecureStorage storage,
  required String runId,
  String? runStatus,
}) async {
  http.on(
    'GET',
    '/api/runs',
    status: 200,
    body: [
      {
        'run_id': runId,
        'status': runStatus ?? 'running',
        'updated_at': '2026-08-15T12:00:00Z',
      },
    ],
  );
  http.on(
    'GET',
    '/api/runs/$runId',
    status: 200,
    body: {'run_id': runId, 'nodes': <dynamic>[]},
  );

  await tester.pumpWidget(
    await _buildHarness(httpTransport: http, storage: storage),
  );
  await pump(tester);
  await tester.tap(find.byKey(const ValueKey('run-row-tap')));
  await pump(tester, 10);
}

/// Every `Text` widget's data currently in the tree, flattened. Used for
/// the achieved-state and sentinel-leak assertions, which must hold
/// against the WHOLE rendered tree, not just one presumed location.
Iterable<String> _allRenderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty);

void main() {
  group('_RunControlRow — routing and confirmation', () {
    testWidgets(
      'pause calls POST /events/{runId}/pause exactly once and renders the '
      'in-flight verb, never an achieved state',
      (tester) async {
        final http = FakeHttpTransport();
        final engine = _installRoutingHttp(tester);
        final storage = _storageWith(engineKey: 'engine-key-pause');
        engine.on('GET', '/workflows', status: 200, body: <dynamic>[]);
        engine.on(
          'POST',
          '/events/run-alpha/pause',
          status: 202,
          body: {'run_id': 'run-alpha', 'status': 'pausing'},
        );

        await _openDetail(
          tester,
          http: http,
          storage: storage,
          runId: 'run-alpha',
          runStatus: 'running',
        );

        await tester.tap(find.byKey(const ValueKey('run-control-pause')));
        await pump(tester, 10);

        expect(engine.callCount('POST', '/events/run-alpha/pause'), 1);
        expect(
          engine.calls
              .firstWhere((c) => c.path == '/events/run-alpha/pause')
              .headers['X-API-Key'],
          'engine-key-pause',
        );
        expect(find.textContaining('Pausing'), findsOneWidget);
        expect(
          _allRenderedText(tester).any((t) => t.contains('Paused')),
          isFalse,
          reason: 'a 202 must never render as an achieved (terminal) state',
        );
      },
    );

    testWidgets(
      'resume calls POST /events/{runId}/resume exactly once and renders '
      'the in-flight verb, never an achieved state',
      (tester) async {
        final http = FakeHttpTransport();
        final engine = _installRoutingHttp(tester);
        final storage = _storageWith(engineKey: 'engine-key-resume');
        engine.on('GET', '/workflows', status: 200, body: <dynamic>[]);
        engine.on(
          'POST',
          '/events/run-beta/resume',
          status: 202,
          body: {
            'run_id': 'run-beta',
            'event_id': 'run-beta',
            'status': 'resuming',
            'resume_at': '2026-08-18T12:00:00Z',
          },
        );

        await _openDetail(
          tester,
          http: http,
          storage: storage,
          runId: 'run-beta',
          runStatus: 'suspended',
        );

        await tester.tap(find.byKey(const ValueKey('run-control-resume')));
        await pump(tester, 10);

        expect(engine.callCount('POST', '/events/run-beta/resume'), 1);
        expect(find.textContaining('Resuming'), findsOneWidget);
        expect(
          _allRenderedText(tester).any((t) => t.contains('Resumed')),
          isFalse,
        );
      },
    );

    testWidgets(
      'abort does not call the abort route until the confirmation sheet is '
      'confirmed; cancelling leaves it uncalled',
      (tester) async {
        final http = FakeHttpTransport();
        final engine = _installRoutingHttp(tester);
        final storage = _storageWith(engineKey: 'engine-key-abort');
        engine.on('GET', '/workflows', status: 200, body: <dynamic>[]);
        engine.on(
          'POST',
          '/events/run-gamma/abort',
          status: 202,
          body: {'run_id': 'run-gamma', 'status': 'aborting'},
        );

        await _openDetail(
          tester,
          http: http,
          storage: storage,
          runId: 'run-gamma',
          runStatus: 'running',
        );

        // Cancel path: the route must not be called.
        await tester.tap(find.byKey(const ValueKey('run-control-abort')));
        await tester.pumpAndSettle();
        expect(find.text('run-gamma'), findsWidgets); // sheet names the run
        await tester.tap(find.byKey(const Key('confirm-sheet-cancel')));
        await tester.pumpAndSettle();
        expect(engine.callCount('POST', '/events/run-gamma/abort'), 0);

        // Confirm path: exactly one call, in-flight message, no achieved
        // state.
        await tester.tap(find.byKey(const ValueKey('run-control-abort')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-sheet-confirm')));
        await pump(tester, 10);

        expect(engine.callCount('POST', '/events/run-gamma/abort'), 1);
        expect(find.textContaining('Aborting'), findsOneWidget);
        expect(
          _allRenderedText(tester).any((t) => t.contains('Aborted')),
          isFalse,
        );
      },
    );

    testWidgets(
      'the two disabled-engine causes render distinguishable reasons: no '
      'key configured vs. engine not mounted',
      (tester) async {
        // Cause 1: no engine key configured at all — the probe is never
        // issued (EngineApi short-circuits before any request).
        final httpA = FakeHttpTransport();
        final storageA = _storageWith(engineKey: null);
        await _openDetail(
          tester,
          http: httpA,
          storage: storageA,
          runId: 'run-no-key',
        );
        final reasonNoKey = tester
            .widget<Text>(
              find.byKey(const ValueKey('run-control-disabled-reason')),
            )
            .data;
        expect(reasonNoKey, isNotNull);
        expect(reasonNoKey, contains('No engine key configured'));
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('run-control-pause')),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'disabled reason distinguishes "engine not mounted" from "no key '
      'configured"',
      (tester) async {
        final httpB = FakeHttpTransport();
        final engineB = _installRoutingHttp(tester);
        final storageB = _storageWith(engineKey: 'engine-key-unmounted');
        engineB.on('GET', '/workflows', status: 404, body: '');

        await _openDetail(
          tester,
          http: httpB,
          storage: storageB,
          runId: 'run-unmounted',
        );

        final reasonUnmounted = tester
            .widget<Text>(
              find.byKey(const ValueKey('run-control-disabled-reason')),
            )
            .data;
        expect(reasonUnmounted, isNotNull);
        expect(reasonUnmounted, contains('not mounted'));
        expect(
          reasonUnmounted,
          isNot(contains('No engine key configured')),
          reason:
              'the two disabled causes must render DISTINCT reason text, '
              'not a shared generic message',
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('run-control-pause')),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      "resume's 422 policy-failure outcome renders the server's message "
      'text, not the generic error string',
      (tester) async {
        final http = FakeHttpTransport();
        final engine = _installRoutingHttp(tester);
        final storage = _storageWith(engineKey: 'engine-key-422');
        engine.on('GET', '/workflows', status: 200, body: <dynamic>[]);
        engine.on(
          'POST',
          '/events/run-delta/resume',
          status: 422,
          body: {
            'error': 'policy resolution failed',
            'message': 'unknown workflow_type: totally-unrecognized-kind',
          },
        );

        await _openDetail(
          tester,
          http: http,
          storage: storage,
          runId: 'run-delta',
          runStatus: 'suspended',
        );

        await tester.tap(find.byKey(const ValueKey('run-control-resume')));
        await pump(tester, 10);

        expect(
          find.text('unknown workflow_type: totally-unrecognized-kind'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a sentinel engine API key appears nowhere in the rendered tree, '
      'including surfaced error text, across probe + control calls',
      (tester) async {
        final http = FakeHttpTransport();
        final engine = _installRoutingHttp(tester);
        final storage = _storageWith(engineKey: _sentinelKey);
        engine.on('GET', '/workflows', status: 200, body: <dynamic>[]);
        // An undocumented status code drives the generic ApiError path in
        // `_handleError`, exercising the error-surfacing branch alongside
        // the happy-path probe.
        engine.on(
          'POST',
          '/events/run-epsilon/pause',
          status: 500,
          body: 'internal error',
        );

        await _openDetail(
          tester,
          http: http,
          storage: storage,
          runId: 'run-epsilon',
          runStatus: 'running',
        );

        expect(
          _allRenderedText(tester).any((t) => t.contains(_sentinelKey)),
          isFalse,
        );

        await tester.tap(find.byKey(const ValueKey('run-control-pause')));
        await pump(tester, 10);

        // The generic error message rendered — never the key.
        expect(
          find.byKey(const ValueKey('run-control-message')),
          findsOneWidget,
        );
        expect(
          _allRenderedText(tester).any((t) => t.contains(_sentinelKey)),
          isFalse,
          reason:
              'Standing Rule 7: the engine key must never surface in any '
              'rendered text, including a control-call error message',
        );
      },
    );
  });
}
