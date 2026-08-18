// Widget tests for the Settings screen's Engine API key field (`BU.12.A`
// task 5).
//
// Covers this task's three acceptance criteria:
//   1. the key round-trips through (fake) `FlutterSecureStorage` under
//      `bastion.auth.engine_key` and touches no other store key;
//   2. a Standing-Rule-7 leak assertion — a distinctive sentinel key must
//      appear in NONE of: any SnackBar shown to the user, the
//      `ConnectionConfig`/`ConnectionState` diagnostic `toString()`s
//      surfaced from provider state, or the accessibility/semantics tree
//      (`obscureText` hides painted glyphs but is a RENDERING property —
//      the SERIALIZATION property is checked separately and independently
//      via `SemanticsNode.value`); and it must appear in the rendered
//      widget tree ONLY inside the engine key field's own live editor,
//      never anywhere else. That last form is deliberate, not a raw
//      `Element.toStringDeep()`-style dump or a bare `find.text(sentinel)
//      == findsNothing`: `find.text()` matches on the underlying text
//      DATA, not painted pixels, so it finds ANY live `TextEditingController`
//      holding the value — including the pre-existing bearer-token field's
//      own controller when given ITS value — regardless of `obscureText`
//      (verified experimentally: `TextField(obscureText: true)` still
//      matches `find.text()` on its own text). A live editor holding its
//      real value to remain editable is not itself a leak; the actual leak
//      surface is the value escaping to somewhere OTHER than its own field
//      — a label, a status line, another field, a snackbar — which is what
//      this file asserts against;
//   3. each of the five `EngineStatus` outcomes renders a distinguishable
//      status line, not a boolean.
//
// `SettingsScreen` wires `EngineApi` straight to the default
// `IoHttpTransport` with no fake-transport injection seam, so the ONLY way
// to control what the widget's probe observes is `dart:io`'s
// `HttpOverrides` — the same mechanism `TestWidgetsFlutterBinding` itself
// uses to make every `HttpClient` synthesize a 400 in ordinary widget
// tests (`flutter_test`'s `_binding_io.dart`, `_MockHttpOverrides`). A
// REAL loopback `HttpServer` was tried first and rejected: `flutter
// test`'s `flutter_tester` engine has no real network access, so with the
// framework's default override left in place every request silently comes
// back as a 400 (never reaching the server), and forcibly clearing the
// override to let a genuine socket through does not fail — it HANGS,
// because the engine has no path to a real socket either. `_FakeHttpClient`
// below installs a second `HttpOverrides` (swapped in per test, restored
// in `tearDown`) that fabricates a specific status/body/exception with no
// socket involved at all, exactly like the framework's own default one —
// this is hermetic, deterministic, and cannot hang.
//
// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/settings_screen.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Fake FlutterSecureStorage (mirrors test/state/connection_provider_test.dart)
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
  }) async {
    return store[key];
  }

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

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return store.containsKey(key);
  }
}

const _kHostKey = 'bastion.server.host';
const _kPortKey = 'bastion.server.port';
const _kTokenKey = 'bastion.auth.token';
const _kEngineKeyKey = 'bastion.auth.engine_key';

const _validHost = '127.0.0.1';
const _validToken = 'a-bearer-token';

const _sentinelKey = 'sentinel-settings-engine-key-do-not-leak-4c91';

/// Pre-populates a fresh [_FakeSecureStorage] with a valid host/port/token
/// plus whatever overrides are given. Only the TOKEN is guaranteed to reach
/// the form fields race-free ([SettingsScreen._loadToken] reads storage
/// directly, independent of [ConnectionNotifier]'s own async load) — tests
/// that need a specific host/port must fill those fields explicitly via
/// [_fillHostPort] rather than trust the initial seed, since
/// `ConnectionNotifier`'s async `_load()` can still be in flight when
/// `initState` first reads `ref.read(connectionProvider).config`.
_FakeSecureStorage _storageWith({
  String host = _validHost,
  int port = 4317,
  String token = _validToken,
  String? engineKey,
}) {
  final storage = _FakeSecureStorage();
  storage.store[_kHostKey] = host;
  storage.store[_kPortKey] = port.toString();
  storage.store[_kTokenKey] = token;
  if (engineKey != null) {
    storage.store[_kEngineKeyKey] = engineKey;
  }
  return storage;
}

// ---------------------------------------------------------------------------
// A fabricated (never-hits-a-socket) HttpOverrides — see the file doc
// comment for why this replaces a real HttpServer.
// ---------------------------------------------------------------------------

class _FakeHttpHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) => <String>[];
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
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) => null;
}

/// A canned [HttpClientResponse] with a configurable status/body and no
/// socket behind it. `extends Stream<Uint8List>` (rather than
/// `implements`) inherits every Stream convenience method (`transform`,
/// `join`, ...) from the base class in terms of [listen] — only [listen]
/// itself needs a real implementation.
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

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest(this._response);

  final _FakeHttpResponse _response;

  @override
  bool bufferOutput = true;
  @override
  int contentLength = -1;
  @override
  late Encoding encoding;
  @override
  bool followRedirects = true;
  @override
  final HttpHeaders headers = _FakeHttpHeaders();
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) => Future<void>.value();
  @override
  Future<HttpClientResponse> close() =>
      Future<HttpClientResponse>.value(_response);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  List<Cookie> get cookies => <Cookie>[];
  @override
  Future<HttpClientResponse> get done async => _response;
  @override
  Future<void> flush() => Future<void>.value();
  @override
  int maxRedirects = 5;
  @override
  String get method => '';
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

/// An [HttpClient] whose every request either resolves to a fixed
/// status/body or throws a fixed exception — never touches a real socket.
class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({this.statusCode, this.body, this.exception});

  final int? statusCode;
  final String? body;
  final Object? exception;

  Future<HttpClientRequest> _make() async {
    if (exception != null) {
      throw exception!;
    }
    return _FakeHttpRequest(_FakeHttpResponse(statusCode!, body!));
  }

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
  void close({bool force = false}) {}
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _make();
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _make();
  @override
  String Function(Uri url)? findProxy;
  @override
  Future<HttpClientRequest> get(String host, int port, String path) => _make();
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _make();
  @override
  Future<HttpClientRequest> head(String host, int port, String path) => _make();
  @override
  Future<HttpClientRequest> headUrl(Uri url) => _make();
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _make();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _make();
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _make();
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _make();
  @override
  Future<HttpClientRequest> post(String host, int port, String path) => _make();
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _make();
  @override
  Future<HttpClientRequest> put(String host, int port, String path) => _make();
  @override
  Future<HttpClientRequest> putUrl(Uri url) => _make();
}

class _FakeHttpOverrides extends HttpOverrides {
  _FakeHttpOverrides({this.statusCode, this.body, this.exception});

  final int? statusCode;
  final String? body;
  final Object? exception;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(statusCode: statusCode, body: body, exception: exception);
}

/// Installs a fabricated response/exception as the process-wide
/// [HttpOverrides] for the duration of one test, restoring whatever was
/// there before (normally `flutter_test`'s own synthetic-400 override) in
/// `tearDown`.
void _installFakeHttp(
  WidgetTester tester, {
  int? statusCode,
  String? body,
  Object? exception,
}) {
  final previous = HttpOverrides.current;
  HttpOverrides.global = _FakeHttpOverrides(
    statusCode: statusCode,
    body: body,
    exception: exception,
  );
  addTearDown(() => HttpOverrides.global = previous);
}

// ---------------------------------------------------------------------------
// Widget helpers
// ---------------------------------------------------------------------------

Finder _fieldByLabel(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

final _hostField = _fieldByLabel('Server host');
final _portField = _fieldByLabel('Port');
final _engineKeyField = _fieldByLabel('Engine API key (optional)');
final _saveButton = find.widgetWithText(FilledButton, 'Save');

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester,
  _FakeSecureStorage storage,
) async {
  // A taller-than-default surface so the whole form — including the Save
  // button below the Engine group — is on-screen without scrolling; a tap
  // on an off-screen widget silently misses (flutter_test only warns, it
  // does not fail), which would make every Save-driven assertion below
  // report the PRE-save state instead of a real failure.
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [secureStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
    ),
  );
  await _settle(tester);
  return container;
}

Future<void> _settle(
  WidgetTester tester, {
  int rounds = 10,
  Duration step = const Duration(milliseconds: 20),
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(step);
  }
}

/// Overwrites the host/port fields with known-good values, deterministically
/// — see the file-level doc comment on why the initial seed cannot be
/// trusted.
Future<void> _fillHostPort(
  WidgetTester tester, {
  String host = _validHost,
  int port = 4317,
}) async {
  await tester.enterText(_hostField, host);
  await tester.enterText(_portField, port.toString());
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Engine API key field', () {
    testWidgets('renders obscured by default', (tester) async {
      await _pumpSettings(tester, _storageWith());

      expect(_engineKeyField, findsOneWidget);
      expect(tester.widget<TextField>(_engineKeyField).obscureText, isTrue);
    });

    testWidgets('is optional — saving with it empty succeeds', (tester) async {
      final storage = _storageWith();
      await _pumpSettings(tester, storage);

      expect(tester.widget<TextField>(_engineKeyField).controller?.text, '');

      await _fillHostPort(tester);
      await tester.tap(_saveButton);
      await _settle(tester);

      expect(find.text('Settings saved'), findsOneWidget);
      // Rest of settings is preserved / re-written unchanged.
      expect(storage.store[_kHostKey], _validHost);
      expect(storage.store[_kTokenKey], _validToken);
      // No engine key was ever written or left behind.
      expect(storage.store.containsKey(_kEngineKeyKey), isFalse);
    });

    testWidgets(
      'entering a key and saving writes it under bastion.auth.engine_key '
      'and no other store key',
      (tester) async {
        final storage = _storageWith();
        await _pumpSettings(tester, storage);

        await _fillHostPort(tester);
        await tester.enterText(_engineKeyField, 'freshly-entered-key');
        await tester.tap(_saveButton);
        await _settle(tester);

        expect(storage.store[_kEngineKeyKey], 'freshly-entered-key');
        // The value landed under exactly one key.
        final matches = storage.store.entries.where(
          (e) => e.value == 'freshly-entered-key',
        );
        expect(matches, hasLength(1));
        expect(matches.single.key, _kEngineKeyKey);
      },
    );

    testWidgets('clearing the field deletes the stored entry', (tester) async {
      final storage = _storageWith(engineKey: 'was-configured');
      await _pumpSettings(tester, storage);

      // The pre-existing key was loaded into the field on init.
      expect(
        tester.widget<TextField>(_engineKeyField).controller?.text,
        'was-configured',
      );

      await _fillHostPort(tester);
      await tester.enterText(_engineKeyField, '');
      await tester.tap(_saveButton);
      await _settle(tester);

      expect(storage.store.containsKey(_kEngineKeyKey), isFalse);
    });
  });

  group('Engine mount status line', () {
    testWidgets('notConfigured — no key held locally', (tester) async {
      await _pumpSettings(tester, _storageWith());

      // No fake HTTP needed: a null/empty key short-circuits before any
      // request is made, regardless of what the transport would answer.
      await _fillHostPort(tester);
      await tester.tap(_saveButton);
      await _settle(tester);

      expect(find.text('NOT CONFIGURED'), findsOneWidget);
    });

    testWidgets('available — a fabricated 200 registry response', (
      tester,
    ) async {
      _installFakeHttp(tester, statusCode: 200, body: jsonEncode(['b', 'a']));

      await _pumpSettings(tester, _storageWith());
      await _fillHostPort(tester);
      await tester.enterText(_engineKeyField, 'good-key');
      await tester.tap(_saveButton);
      await _settle(tester);

      expect(find.text('CONNECTED'), findsOneWidget);
    });

    testWidgets('unauthorized — a fabricated 401', (tester) async {
      _installFakeHttp(
        tester,
        statusCode: 401,
        body: jsonEncode({'code': 'unauthorized'}),
      );

      await _pumpSettings(tester, _storageWith());
      await _fillHostPort(tester);
      await tester.enterText(_engineKeyField, 'wrong-key');
      await tester.tap(_saveButton);
      await _settle(tester);

      expect(find.text('KEY REJECTED'), findsOneWidget);
    });

    testWidgets('notMounted — a fabricated 404 (engine routes absent)', (
      tester,
    ) async {
      _installFakeHttp(tester, statusCode: 404, body: '');

      await _pumpSettings(tester, _storageWith());
      await _fillHostPort(tester);
      await tester.enterText(_engineKeyField, 'some-key');
      await tester.tap(_saveButton);
      await _settle(tester);

      expect(find.text('ENGINE NOT MOUNTED ON THIS SERVER'), findsOneWidget);
    });

    testWidgets('unreachable — a fabricated socket-level failure', (
      tester,
    ) async {
      _installFakeHttp(
        tester,
        exception: const SocketException('connection refused (fake)'),
      );

      await _pumpSettings(tester, _storageWith());
      await _fillHostPort(tester);
      await tester.enterText(_engineKeyField, 'some-key');
      await tester.tap(_saveButton);
      await _settle(tester);

      expect(find.text('SERVER UNREACHABLE'), findsOneWidget);
    });
  });

  group('Standing Rule 7 — sentinel key never leaks', () {
    testWidgets(
      'sentinel is absent from rendered text, semantics, snackbars, and '
      'ConnectionConfig/ConnectionState diagnostics',
      (tester) async {
        final storage = _storageWith(engineKey: _sentinelKey);
        final container = await _pumpSettings(tester, storage);

        // 1. `find.text()` matches on the underlying text DATA, not on
        //    painted pixels — it finds the engine key field's own
        //    `EditableText` even though `obscureText: true` renders dots,
        //    because a live editor must hold its real value to be
        //    editable at all (verified: asserting `findsNothing` here
        //    fails against the field itself, not against a leak). The
        //    meaningful check is therefore that the sentinel appears
        //    EXACTLY where it is expected to — inside its own field's
        //    live editor — and nowhere else in the rendered tree (no
        //    label, status line, or other field echoes it).
        expect(find.text(_sentinelKey), findsOneWidget);
        expect(
          find.descendant(
            of: _engineKeyField,
            matching: find.text(_sentinelKey),
          ),
          findsOneWidget,
        );

        // 2. Accessibility / semantics tree — a screen reader must not be
        //    handed the plaintext either. Obscuring is a RENDERING
        //    property; this checks the separate SERIALIZATION property.
        final semanticsHandle = tester.ensureSemantics();
        final fieldSemantics = tester.getSemantics(_engineKeyField);
        expect(fieldSemantics.value, isNot(contains(_sentinelKey)));
        expect(fieldSemantics.label, isNot(contains(_sentinelKey)));
        semanticsHandle.dispose();

        // 3. Trigger a save (round-trips through the notifier + a probe)
        //    and confirm the confirmation SnackBar carries no key. The
        //    probe itself hits the framework's default synthetic-400
        //    override (harmless and fast — no real socket either way).
        await _fillHostPort(tester);
        await tester.tap(_saveButton);
        await _settle(tester);
        final snackBarTexts = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data ?? '');
        for (final text in snackBarTexts) {
          expect(text, isNot(contains(_sentinelKey)));
        }

        // 4. The app's own diagnostic value objects — Standing Rule 7
        //    names `toString()` explicitly. Neither carries the key by
        //    construction (task 1); re-assert at the widget-integration
        //    layer, from the live provider state this screen reads.
        final state = container.read(connectionProvider);
        expect(state.toString(), isNot(contains(_sentinelKey)));
        expect(state.config.toString(), isNot(contains(_sentinelKey)));
      },
    );
  });
}
