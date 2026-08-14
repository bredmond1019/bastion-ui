// Widget tests for SessionDetailScreen (pane_view.dart + approve_button_row.dart).
//
// Wires a real `paneProvider`/`bastionApiProvider` pair backed by fake
// transports (mirrors `pane_provider_test.dart`'s fixtures) so these tests
// exercise the actual provider + widget wiring end to end, not just a mocked
// override.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/session_detail_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';

// ---------------------------------------------------------------------------
// Fakes (mirrors pane_provider_test.dart / api_test.dart fixtures)
// ---------------------------------------------------------------------------

class FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();
  final List<String> sent = [];

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  void addMessage(String msg) => _controller.add(msg);

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream<dynamic> get messageStream => _controller.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

typedef RecordedCall = ({String method, String url, String? body});

/// [HttpTransport] fake that records every call and consumes queued
/// responses FIFO regardless of method.
final class FakeHttpTransport implements HttpTransport {
  final List<RecordedCall> calls = [];
  final List<({int statusCode, String body})> _responses = [];

  void setResponse({required int statusCode, required Object body}) {
    final encoded = body is String ? body : jsonEncode(body);
    _responses.add((statusCode: statusCode, body: encoded));
  }

  ({int statusCode, String body}) _consume() {
    if (_responses.isEmpty) {
      // Default success for POST/DELETE calls not explicitly stubbed (e.g.
      // approve-button taps) — a 204 with an empty body.
      return (statusCode: 204, body: '');
    }
    return _responses.removeAt(0);
  }

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    calls.add((method: 'GET', url: url, body: null));
    return _consume();
  }

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    calls.add((method: 'POST', url: url, body: body));
    return _consume();
  }

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    calls.add((method: 'DELETE', url: url, body: null));
    return _consume();
  }
}

/// Pump the microtask/timer queue so async work (handshake, seed fetch,
/// frame decoding) settles.
///
/// Advances by a non-zero duration per round so rxdart's
/// `.debounceTime(~150ms)` on the provider-layer WS stream (see
/// `lib/state/pane_provider.dart`) has enough fake-clock time to fire within
/// the default 5 rounds (200ms total) — `flutter_test`'s widget bindings run
/// inside a `FakeAsync` zone, so `Timer`s only advance when `tester.pump`
/// is given an explicit duration.
Future<void> pump(WidgetTester tester, [int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<(BastionSocket, FakeWsTransport)> makeConnectedSocket(
  WidgetTester tester,
) async {
  final transports = <FakeWsTransport>[];
  final socket = BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transportFactory: (uri, {headers}) {
      final t = FakeWsTransport();
      transports.add(t);
      return t;
    },
  );
  socket.connect();
  await pump(tester);
  transports.single.completeReady();
  await pump(tester);
  return (socket, transports.single);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionDetailScreen', () {
    late BastionSocket socket;
    late FakeWsTransport wsTransport;
    late FakeHttpTransport httpTransport;
    late BastionApi api;
    late ProviderContainer parentContainer;

    setUp(() {
      httpTransport = FakeHttpTransport();
      api = BastionApi(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transport: httpTransport,
      );
    });

    tearDown(() async {
      await socket.dispose();
    });

    Future<void> pumpScreen(
      WidgetTester tester, {
      required String sessionName,
    }) async {
      final (s, t) = await makeConnectedSocket(tester);
      socket = s;
      wsTransport = t;
      parentContainer = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );
      addTearDown(parentContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: parentContainer,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: SessionDetailScreen(sessionName: sessionName),
          ),
        ),
      );
      await pump(tester);
    }

    testWidgets('renders the pane buffer seeded via REST getPane()', (
      tester,
    ) async {
      httpTransport.setResponse(
        statusCode: 200,
        body: {
          'session_name': 'alpha',
          'lines': [r'$ ls', 'foo.txt'],
        },
      );

      await pumpScreen(tester, sessionName: 'alpha');

      expect(find.textContaining(r'$ ls'), findsOneWidget);
      expect(find.textContaining('foo.txt'), findsOneWidget);
    });

    testWidgets('auto-scrolls to the bottom when a new pane frame arrives', (
      tester,
    ) async {
      httpTransport.setResponse(
        statusCode: 200,
        body: {'session_name': 'alpha', 'lines': <String>[]},
      );

      await pumpScreen(tester, sessionName: 'alpha');

      final manyLines = List.generate(200, (i) => 'line $i');

      // Push a WS pane frame with enough lines to overflow the viewport.
      wsTransport.addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {'session': 'alpha', 'seq': 1, 'lines': manyLines},
        }),
      );
      await pump(tester);

      final scrollableFinder = find.byType(SingleChildScrollView);
      expect(scrollableFinder, findsOneWidget);
      final scrollable = tester.widget<SingleChildScrollView>(scrollableFinder);
      final controller = scrollable.controller!;
      expect(controller.hasClients, isTrue);
      expect(controller.offset, controller.position.maxScrollExtent);
      expect(controller.offset, greaterThan(0));
    });

    for (final entry in const {
      'y': (method: 'sendKeys', key: 'y'),
      'Enter': (method: 'sendKey', key: 'Enter'),
      'Esc': (method: 'sendKey', key: 'Escape'),
      '1': (method: 'sendKeys', key: '1'),
      '2': (method: 'sendKeys', key: '2'),
    }.entries) {
      testWidgets(
        'tapping the "${entry.key}" approve button sends the right key',
        (tester) async {
          httpTransport.setResponse(
            statusCode: 200,
            body: {'session_name': 'alpha', 'lines': <String>[]},
          );

          await pumpScreen(tester, sessionName: 'alpha');
          httpTransport.calls.clear();

          await tester.tap(find.byKey(ValueKey('approve-${entry.key}')));
          await pump(tester);

          expect(httpTransport.calls, hasLength(1));
          final call = httpTransport.calls.single;
          expect(call.method, 'POST');
          if (entry.value.method == 'sendKeys') {
            expect(call.url, contains('/api/sessions/alpha/send'));
            expect(jsonDecode(call.body!), {'keys': entry.value.key});
          } else {
            expect(call.url, contains('/api/sessions/alpha/key'));
            expect(jsonDecode(call.body!), {'key': entry.value.key});
          }
        },
      );
    }

    testWidgets('the send bar sends typed keys and clears the field', (
      tester,
    ) async {
      httpTransport.setResponse(
        statusCode: 200,
        body: {'session_name': 'alpha', 'lines': <String>[]},
      );

      await pumpScreen(tester, sessionName: 'alpha');
      httpTransport.calls.clear();

      await tester.enterText(
        find.byKey(const ValueKey('send-bar-field')),
        'hello world',
      );
      await tester.tap(find.byKey(const ValueKey('send-bar-button')));
      await pump(tester);

      expect(httpTransport.calls, hasLength(1));
      final call = httpTransport.calls.single;
      expect(call.url, contains('/api/sessions/alpha/send'));
      expect(jsonDecode(call.body!), {'keys': 'hello world'});

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('send-bar-field')),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('renders brand primitives: an Eyebrow per section and the pane '
        'wrapped in a PanelCard', (tester) async {
      httpTransport.setResponse(
        statusCode: 200,
        body: {'session_name': 'alpha', 'lines': <String>[]},
      );

      await pumpScreen(tester, sessionName: 'alpha');

      expect(find.byType(Eyebrow), findsNWidgets(2));
      expect(find.text('TERMINAL'), findsOneWidget);
      expect(find.text('QUICK APPROVE'), findsOneWidget);
      expect(find.byType(PanelCard), findsOneWidget);
    });

    testWidgets(
      'the deny ("Esc") button is destructive-toned and the affirmative '
      'buttons are primary-toned, both from AppTokens',
      (tester) async {
        httpTransport.setResponse(
          statusCode: 200,
          body: {'session_name': 'alpha', 'lines': <String>[]},
        );

        await pumpScreen(tester, sessionName: 'alpha');

        final escButton = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('approve-Esc')),
        );
        expect(
          escButton.style?.foregroundColor?.resolve({}),
          AppTokens.destructive,
        );

        final yButton = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('approve-y')),
        );
        expect(yButton.style?.foregroundColor?.resolve({}), AppTokens.primary);
      },
    );
  });
}
