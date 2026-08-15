// ignore_for_file: avoid_relative_lib_imports
//
// `briefing_provider.dart` (BU.13.B task 3) tests, built on the shared
// integration-tier fixtures (`test/support/fake_http_transport.dart`,
// `test/support/wire_fixtures.dart` — BU.ticket.integration-test-tier), not
// a new bespoke fake.
//
// The sessions section under test wraps [sessionsProvider] as-is, so a
// connected fake [BastionSocket] is required to construct it — the fake
// socket/transport pair here mirrors `test/state/sessions_provider_test.dart`
// (that file's own header notes it mirrors `reconnect_test.dart` /
// `api_test.dart` in turn; each provider test file keeps its own copy by
// established convention in this repo).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/models/attention_dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/briefing_model.dart';
import 'package:bastion_ui/state/briefing_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart';

import '../support/fake_http_transport.dart';
import '../support/wire_fixtures.dart';

// ---------------------------------------------------------------------------
// Fake WS transport (mirrors sessions_provider_test.dart)
// ---------------------------------------------------------------------------

class FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

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
}

/// `GET /api/board` fixture whose `blocked` lane carries
/// [boardBlockFullFixture] — that block's `blocked_by` includes an
/// `operator` dependency, so it ranks as an operator gate
/// (`rankOperatorGates`). `boardHqFixture` puts the same block in `now`, so
/// tests that need a non-empty `rankedGates` use this instead.
const Map<String, dynamic> boardWithGateFixture = {
  'scope': 'hq',
  'lanes': {
    'now': <dynamic>[],
    'next': <dynamic>[],
    'blocked': [boardBlockFullFixture],
    'deferred': <dynamic>[],
    'finished': <dynamic>[],
  },
  'stale': false,
};

Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

Future<BastionSocket> makeConnectedSocket() async {
  FakeWsTransport? transport;
  final socket = BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transportFactory: (uri, {headers}) {
      final t = FakeWsTransport();
      transport = t;
      return t;
    },
  );
  socket.connect();
  await pump();
  transport!.completeReady();
  await pump();
  return socket;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeHttpTransport httpTransport;
  late BastionApi api;
  late BastionSocket socket;
  late ProviderContainer container;

  setUp(() async {
    httpTransport = FakeHttpTransport();
    api = BastionApi(
      host: 'test-host',
      port: 4317,
      token: 'test-token',
      transport: httpTransport,
    );
    socket = await makeConnectedSocket();
    // sessionsProvider seeds via GET /api/sessions on construction — every
    // test in this file needs a route registered even when sessions
    // themselves are not the thing under test.
    httpTransport.on(
      'GET',
      '/api/sessions',
      status: 200,
      body: sessionsFixture,
    );

    container = ProviderContainer();
    container.read(bastionApiProvider.notifier).state = api;
    container.read(bastionSocketProvider.notifier).state = socket;
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await socket.dispose();
  });

  group('briefingBoardProvider / briefingAttentionProvider — success', () {
    test(
      'both sections load independently and populate the view model',
      () async {
        httpTransport.on(
          'GET',
          '/api/board',
          status: 200,
          body: boardHqFixture,
        );
        httpTransport.on(
          'GET',
          '/api/attention',
          status: 200,
          body: attentionFixture,
        );

        // Reading each provider triggers its notifier's construction (and
        // thus its fetch) — both must be read before `pump()` or the later
        // one's fetch will not have started yet when assertions run.
        expect(
          container.read(briefingBoardProvider),
          isA<BriefingSectionLoading<BoardDto>>(),
        );
        expect(
          container.read(briefingAttentionProvider),
          isA<BriefingSectionLoading<AttentionDto>>(),
        );
        await pump();

        final board = container.read(briefingBoardProvider);
        final attention = container.read(briefingAttentionProvider);
        expect(board, isA<BriefingSectionLoaded<BoardDto>>());
        expect(attention, isA<BriefingSectionLoaded<AttentionDto>>());

        final vm = container.read(briefingViewModelProvider);
        expect(vm.board.dataOrNull, isNotNull);
        expect(vm.attention.dataOrNull, isNotNull);
        expect(vm.sessions.dataOrNull, isNotNull);

        // graph=true is sent on every board fetch (the cost decision recorded
        // in briefing_provider.dart's doc comment).
        final call = httpTransport.lastCallTo('GET', '/api/board');
        expect(call, isNotNull);
        expect(call!.queryParameters['graph'], 'true');
      },
    );
  });

  group(
    'briefingBoardProvider / briefingAttentionProvider — partial failure',
    () {
      test(
        'board OK + attention 500 leaves board loaded and only attention errored',
        () async {
          httpTransport.on(
            'GET',
            '/api/board',
            status: 200,
            body: boardWithGateFixture,
          );
          httpTransport.on(
            'GET',
            '/api/attention',
            status: 500,
            body: {'error': 'internal', 'code': 'C000', 'message': 'boom'},
          );

          // Trigger both notifiers before pumping (see the note in the
          // "success" group above).
          container.read(briefingBoardProvider);
          container.read(briefingAttentionProvider);
          await pump();

          final board = container.read(briefingBoardProvider);
          final attention = container.read(briefingAttentionProvider);
          expect(board, isA<BriefingSectionLoaded<BoardDto>>());
          expect(attention, isA<BriefingSectionError<AttentionDto>>());
          expect(
            (attention as BriefingSectionError<AttentionDto>).message,
            isNotEmpty,
          );

          // The surviving section's data still reaches the combined view
          // model — a failing sibling section must not blank it.
          final vm = container.read(briefingViewModelProvider);
          expect(vm.board.dataOrNull, isNotNull);
          expect(vm.attention.isError, isTrue);
          expect(vm.rankedGates, isNotEmpty);
        },
      );
    },
  );

  group('refreshFailedBriefingSections', () {
    test('re-fetches only the section(s) that errored', () async {
      httpTransport.on('GET', '/api/board', status: 200, body: boardHqFixture);
      httpTransport.onSequence('GET', '/api/attention', [
        (
          status: 500,
          body: {'error': 'internal', 'code': 'C000', 'message': 'boom'},
        ),
        (status: 200, body: attentionFixture),
      ]);

      container.read(briefingBoardProvider);
      container.read(briefingAttentionProvider);
      await pump();
      expect(
        container.read(briefingAttentionProvider),
        isA<BriefingSectionError<AttentionDto>>(),
      );
      expect(httpTransport.callCount('GET', '/api/board'), 1);
      expect(httpTransport.callCount('GET', '/api/attention'), 1);

      await refreshFailedBriefingSections(container);
      await pump();

      // Attention retried and now loaded ...
      expect(
        container.read(briefingAttentionProvider),
        isA<BriefingSectionLoaded<AttentionDto>>(),
      );
      expect(httpTransport.callCount('GET', '/api/attention'), 2);
      // ... but the already-loaded board was left alone.
      expect(httpTransport.callCount('GET', '/api/board'), 1);
    });

    test('no-ops when nothing failed', () async {
      httpTransport.on('GET', '/api/board', status: 200, body: boardHqFixture);
      httpTransport.on(
        'GET',
        '/api/attention',
        status: 200,
        body: attentionFixture,
      );

      container.read(briefingBoardProvider);
      container.read(briefingAttentionProvider);
      await pump();
      expect(httpTransport.callCount('GET', '/api/board'), 1);
      expect(httpTransport.callCount('GET', '/api/attention'), 1);

      await refreshFailedBriefingSections(container);
      await pump();

      expect(httpTransport.callCount('GET', '/api/board'), 1);
      expect(httpTransport.callCount('GET', '/api/attention'), 1);
    });
  });

  group('unset guards', () {
    test(
      'briefingBoardProvider/briefingAttentionProvider throw before connect',
      () {
        final freshContainer = ProviderContainer();
        addTearDown(freshContainer.dispose);
        expect(
          () => freshContainer.read(briefingBoardProvider),
          throwsA(isA<StateError>()),
        );
        expect(
          () => freshContainer.read(briefingAttentionProvider),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
