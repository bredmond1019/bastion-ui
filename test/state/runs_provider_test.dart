// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/runs_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fakes (mirrors sessions_provider_test.dart / reconnect_resubscribe_test.dart)
// ---------------------------------------------------------------------------

class FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();
  final List<String> sent = [];
  bool closed = false;

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  void addMessage(String msg) => _controller.add(msg);

  /// Simulate a server-side disconnect (a clean stream close) so the
  /// [BastionSocket] schedules a reconnect.
  void drop() {
    if (!_controller.isClosed) _controller.close();
  }

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream<dynamic> get messageStream => _controller.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }
}

/// Pump the microtask/timer queue so async work (handshake, seed fetch,
/// frame decoding) settles.
Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Build a connected [BastionSocket] backed by a [FakeWsTransport].
///
/// [transports] (optional) collects every transport the socket creates —
/// including replacement transports created on a drop+reconnect — so
/// reconnect-focused tests can reach the *next* fake transport after
/// [FakeWsTransport.drop].
Future<(BastionSocket, FakeWsTransport)> makeConnectedSocket({
  List<FakeWsTransport>? transports,
  Duration Function(int attempt)? backoffSchedule,
}) async {
  final ts = transports ?? <FakeWsTransport>[];
  final socket = BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    backoffSchedule: backoffSchedule,
    transportFactory: (uri, {headers}) {
      final t = FakeWsTransport();
      ts.add(t);
      return t;
    },
  );
  socket.connect();
  await pump();
  ts.single.completeReady();
  await pump();
  return (socket, ts.single);
}

Map<String, dynamic> runTransitionFrame({
  required String runId,
  required String status,
  bool terminal = false,
  String? specSlug,
}) => {
  'kind': 'event',
  'payload': {
    'session': '',
    'event': 'run_transition',
    'run_id': runId,
    'status': status,
    'terminal': terminal,
    'spec_slug': ?specSlug,
  },
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('runsProvider — unset guard', () {
    test('throws StateError when read before connect', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(() => container.read(runsProvider), throwsA(isA<StateError>()));
    });
  });

  group('runsProvider', () {
    late BastionSocket socket;
    late FakeWsTransport transport;
    late FakeHttpTransport httpTransport;
    late BastionApi api;
    late ProviderContainer container;

    setUp(() async {
      final (s, t) = await makeConnectedSocket();
      socket = s;
      transport = t;
      httpTransport = FakeHttpTransport();
      api = BastionApi(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transport: httpTransport,
      );
    });

    tearDown(() async {
      container.dispose();
      await socket.dispose();
    });

    test('subscribes to the "runs" topic on first read', () async {
      httpTransport.on(
        'GET',
        '/api/runs',
        status: 200,
        body: <Map<String, dynamic>>[],
      );
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      container.read(runsProvider);
      await pump();

      expect(transport.sent, [jsonEncode(ClientFrames.subscribe(runsTopic))]);
    });

    test('seeds state from REST getRuns() before any WS frame', () async {
      httpTransport.on(
        'GET',
        '/api/runs',
        status: 200,
        body: [
          {
            'run_id': 'r-1',
            'status': 'running',
            'spec_slug': '11.T-run-summary-projection',
          },
        ],
      );
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      container.read(runsProvider);
      await pump();

      final runs = container.read(runsProvider);
      expect(runs, hasLength(1));
      expect(runs.single.runId, 'r-1');
      expect(runs.single.status, 'running');
    });

    test('an empty GET /api/runs (no engine mounted) seeds an empty list, '
        'not an error', () async {
      httpTransport.on(
        'GET',
        '/api/runs',
        status: 200,
        body: <Map<String, dynamic>>[],
      );
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      container.read(runsProvider);
      await pump();

      expect(container.read(runsProvider), isEmpty);
    });

    test(
      'a pushed run_transition frame updates state without any UI action',
      () async {
        httpTransport.on(
          'GET',
          '/api/runs',
          status: 200,
          body: [
            {'run_id': 'r-1', 'status': 'pending'},
          ],
        );
        container = ProviderContainer(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => socket),
            bastionApiProvider.overrideWith((ref) => api),
          ],
        );

        container.read(runsProvider);
        await pump();
        expect(container.read(runsProvider).single.status, 'pending');

        transport.addMessage(
          jsonEncode(runTransitionFrame(runId: 'r-1', status: 'running')),
        );
        await pump();

        final runs = container.read(runsProvider);
        expect(runs, hasLength(1));
        expect(runs.single.status, 'running');
      },
    );

    test('a suspended transition leaves the run live (status suspended, still '
        'present)', () async {
      httpTransport.on(
        'GET',
        '/api/runs',
        status: 200,
        body: [
          {'run_id': 'r-1', 'status': 'running'},
        ],
      );
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      container.read(runsProvider);
      await pump();

      transport.addMessage(
        jsonEncode(
          runTransitionFrame(
            runId: 'r-1',
            status: 'suspended',
            terminal: false,
          ),
        ),
      );
      await pump();

      final runs = container.read(runsProvider);
      expect(runs, hasLength(1));
      expect(runs.single.status, 'suspended');
    });

    test('a terminal:true transition removes the run from state (lifecycle-'
        'terminal, mirroring what a fresh GET /api/runs would no longer '
        'return)', () async {
      httpTransport.on(
        'GET',
        '/api/runs',
        status: 200,
        body: [
          {'run_id': 'r-1', 'status': 'running'},
        ],
      );
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      container.read(runsProvider);
      await pump();
      expect(container.read(runsProvider), hasLength(1));

      transport.addMessage(
        jsonEncode(
          runTransitionFrame(runId: 'r-1', status: 'success', terminal: true),
        ),
      );
      await pump();

      expect(container.read(runsProvider), isEmpty);
    });

    test('sends "unsubscribe" for the "runs" topic on dispose', () async {
      httpTransport.on(
        'GET',
        '/api/runs',
        status: 200,
        body: <Map<String, dynamic>>[],
      );
      // Local, test-owned container so it can be disposed inline without
      // conflicting with the shared `tearDown`'s dispose of `container`.
      final localContainer = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      localContainer.read(runsProvider);
      await pump();
      localContainer.dispose();

      expect(
        transport.sent,
        contains(jsonEncode(ClientFrames.unsubscribe(runsTopic))),
      );

      // Satisfy tearDown's container.dispose() with a fresh, undisposed
      // container (the shared `container` field was never assigned above).
      container = ProviderContainer();
    });

    test(
      'periodic re-seed picks up a run that appeared and stayed at one '
      'status the whole time — the run_transition gap this safety net '
      'exists for (serve-api.md §8.3, D17: no push on first observation)',
      () async {
        httpTransport.onSequence('GET', '/api/runs', [
          (status: 200, body: <Map<String, dynamic>>[]),
          (
            status: 200,
            body: [
              {'run_id': 'r-new', 'status': 'running'},
            ],
          ),
        ]);
        container = ProviderContainer(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => socket),
            bastionApiProvider.overrideWith((ref) => api),
            runsReseedIntervalProvider.overrideWithValue(
              const Duration(milliseconds: 20),
            ),
          ],
        );

        container.read(runsProvider);

        // No run_transition frame ever arrives for 'r-new' (by design, per
        // D17) — only the periodic re-seed can surface it.
        await pump(10);

        final runs = container.read(runsProvider);
        expect(runs, hasLength(1));
        expect(runs.single.runId, 'r-new');
        expect(runs.single.status, 'running');
      },
    );

    test('reconnect re-subscribes exactly once', () async {
      // This test needs its own socket (zero backoff, and access to every
      // transport it creates) rather than the shared `setUp` socket.
      final reconnectTransports = <FakeWsTransport>[];
      final (reconnectSocket, firstTransport) = await makeConnectedSocket(
        transports: reconnectTransports,
        backoffSchedule: (_) => Duration.zero,
      );

      httpTransport.on(
        'GET',
        '/api/runs',
        status: 200,
        body: <Map<String, dynamic>>[],
      );
      final localContainer = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => reconnectSocket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );
      localContainer.read(runsProvider);
      await pump();

      // The notifier's own constructor subscribed once, on the first
      // transport.
      expect(firstTransport.sent, [
        jsonEncode(ClientFrames.subscribe(runsTopic)),
      ]);

      // Drop -> the socket reconnects (zero backoff) and replays the active
      // topic registry exactly once — the notifier itself never re-sends a
      // subscribe frame.
      firstTransport.drop();
      await pump();
      expect(
        reconnectTransports,
        hasLength(2),
        reason: 'a replacement transport should exist after the drop',
      );
      reconnectTransports[1].completeReady();
      await pump();

      expect(reconnectTransports[1].sent, [
        jsonEncode(ClientFrames.subscribe(runsTopic)),
      ]);

      localContainer.dispose();
      await reconnectSocket.dispose();
    });
  });
}
