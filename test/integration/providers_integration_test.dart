// Integration tier for the riverpod state layer
// (BU.ticket.integration-test-tier task 4).
//
// Untagged by design — these tests must run inside the gating
// `flutter test --exclude-tags e2e` command, same as task 3's
// `bastion_api_integration_test.dart` (see
// `planning/ticket-integration-test-tier/tasks.md` Notes, "On not tagging
// the tier").
//
// Builds a real `ProviderContainer` on the app's single root provider graph
// (decision D2 — no nested `ProviderScope`) and wires a real `BastionApi`
// over the routing `FakeHttpTransport` (task 1) fed with the wire-shaped
// fixtures (task 2). `bastionApiProvider` is set via the container override
// list; `bastionSocketProvider` is set the same way the real app shell sets
// it — `container.read(bastionSocketProvider.notifier).state = socket` —
// mirroring the doc comment on `sessions_provider.dart`'s injection points
// rather than a `ProviderScope` override, since `sessionsProvider` and
// `repoWorkflowsProvider` both require a live `BastionSocket` instance (not
// just a fake transport) to construct.
//
// Covers `reposProvider`, `sessionsProvider` and `repoWorkflowsProvider`
// each reaching correct state from an initial seed, a live update
// (`refresh()` for repos, a WS `sessions` snapshot for sessions, a WS
// `workflow_done` event for workflows), and an empty-collection payload
// rendering as empty rather than throwing. Also asserts the documented
// failure behaviour: `RepoListNotifier.refresh` leaves previous state in
// place on a failed fetch.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/repos_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart';
import 'package:bastion_ui/state/workflows_provider.dart';

import '../support/fake_http_transport.dart';
import '../support/wire_fixtures.dart';

const _host = '127.0.0.1';
const _port = 4317;
const _token = 'test-token-123';

// ---------------------------------------------------------------------------
// WS transport fake (mirrors sessions_provider_test.dart's FakeWsTransport)
// ---------------------------------------------------------------------------

class _FakeWsTransport implements WsTransport {
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

/// Pump the microtask/timer queue so async work (handshake, seed fetch,
/// frame decoding, the ~150ms debounce in sessions/workflows providers)
/// settles.
Future<void> _pump([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// Build a real, connected [BastionSocket] backed by a fake transport (no
/// network), and wire it into [container] the same way the app shell does.
Future<_FakeWsTransport> _connectSocket(ProviderContainer container) async {
  final ws = _FakeWsTransport();
  final socket = BastionSocket(
    host: _host,
    port: _port,
    token: _token,
    transportFactory: (uri, {headers}) => ws,
  );
  addTearDown(socket.dispose);
  container.read(bastionSocketProvider.notifier).state = socket;
  socket.connect();
  await _pump();
  ws.completeReady();
  await _pump();
  return ws;
}

/// Build a [ProviderContainer] wired to a real [BastionApi] over
/// [transport], with `bastionApiProvider` overridden — the single
/// container-level override this ticket calls for (D2: single root
/// container, overrides only).
ProviderContainer _makeContainer(FakeHttpTransport transport) {
  final api = BastionApi(
    host: _host,
    port: _port,
    token: _token,
    transport: transport,
  );
  final container = ProviderContainer(
    overrides: [bastionApiProvider.overrideWith((ref) => api)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('reposProvider', () {
    test('seeds from GET /api/repos', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/repos', status: 200, body: reposFixture);
      final container = _makeContainer(t);

      container.listen(reposProvider, (_, _) {});
      await _pump();

      final repos = container.read(reposProvider);
      expect(repos, hasLength(2));
      expect(repos[0].name, 'bastion-ui');
      expect(repos[1].name, 'mev');
    });

    test('empty-collection fixture renders as empty, not a throw', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/repos', status: 200, body: reposEmptyFixture);
      final container = _makeContainer(t);

      container.listen(reposProvider, (_, _) {});
      await _pump();

      expect(container.read(reposProvider), isEmpty);
    });

    test('refresh() picks up a changed list', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/repos', status: 200, body: reposEmptyFixture)
        ..on('GET', '/api/repos', status: 200, body: reposFixture);
      final container = _makeContainer(t);

      container.listen(reposProvider, (_, _) {});
      await _pump();
      expect(container.read(reposProvider), isEmpty);

      await container.read(reposProvider.notifier).refresh();
      await _pump();

      expect(container.read(reposProvider), hasLength(2));
      expect(t.callCount('GET', '/api/repos'), 2);
    });

    test(
      'refresh() leaves previous state in place on a failed fetch',
      () async {
        final t = FakeHttpTransport()
          ..on('GET', '/api/repos', status: 200, body: reposFixture)
          ..on('GET', '/api/repos', status: 500, body: notFoundErrorFixture);
        final container = _makeContainer(t);

        container.listen(reposProvider, (_, _) {});
        await _pump();
        expect(container.read(reposProvider), hasLength(2));

        await container.read(reposProvider.notifier).refresh();
        await _pump();

        // The failed refresh must not blank (or otherwise mutate) the
        // previously-seeded list — RepoListNotifier.refresh's doc comment
        // claims this explicitly.
        expect(container.read(reposProvider), hasLength(2));
        expect(container.read(reposProvider)[0].name, 'bastion-ui');
      },
    );
  });

  group('sessionsProvider', () {
    test('seeds from GET /api/sessions', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/sessions', status: 200, body: sessionsFixture);
      final container = _makeContainer(t);
      await _connectSocket(container);

      container.listen(sessionsProvider, (_, _) {});
      await _pump();

      final sessions = container.read(sessionsProvider);
      expect(sessions, hasLength(2));
      expect(sessions[0].name, 'main');
      expect(sessions[1].name, 'idle-session');
    });

    test('empty-collection fixture renders as empty, not a throw', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/sessions', status: 200, body: sessionsEmptyFixture);
      final container = _makeContainer(t);
      await _connectSocket(container);

      container.listen(sessionsProvider, (_, _) {});
      await _pump();

      expect(container.read(sessionsProvider), isEmpty);
    });

    test(
      'a pushed WS "sessions" snapshot replaces REST-seeded state',
      () async {
        final t = FakeHttpTransport()
          ..on('GET', '/api/sessions', status: 200, body: sessionsFixture);
        final container = _makeContainer(t);
        final ws = await _connectSocket(container);

        container.listen(sessionsProvider, (_, _) {});
        await _pump();
        expect(container.read(sessionsProvider), hasLength(2));

        final frame = SessionsFrame(sessions: const []);
        ws.addMessage(jsonEncode(frame.toJson()));
        await _pump();

        expect(container.read(sessionsProvider), isEmpty);
      },
    );
  });

  group('repoWorkflowsProvider', () {
    const repoName = 'bastion-ui';

    test('seeds status + workflows for a repo', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/$repoName/status',
          status: 200,
          body: repoStatusFullFixture,
        )
        ..on(
          'GET',
          '/api/repos/$repoName/workflows',
          status: 200,
          body: workflowsFixture,
        );
      final container = _makeContainer(t);
      await _connectSocket(container);

      container.listen(repoWorkflowsProvider(repoName), (_, _) {});
      await _pump();

      final state = container.read(repoWorkflowsProvider(repoName));
      expect(state.loading, isFalse);
      expect(state.status?.name, repoName);
      expect(state.workflows, hasLength(1));
      expect(state.workflows[0].specSlug, '2.A-dashboard-repo-detail');
    });

    test('empty-collection workflows fixture renders as empty', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/$repoName/status',
          status: 200,
          body: repoStatusMinimalFixture,
        )
        ..on(
          'GET',
          '/api/repos/$repoName/workflows',
          status: 200,
          body: workflowsEmptyFixture,
        );
      final container = _makeContainer(t);
      await _connectSocket(container);

      container.listen(repoWorkflowsProvider(repoName), (_, _) {});
      await _pump();

      final state = container.read(repoWorkflowsProvider(repoName));
      expect(state.loading, isFalse);
      expect(state.workflows, isEmpty);
    });

    test('a matching workflow_done event triggers a re-fetch', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/$repoName/status',
          status: 200,
          body: repoStatusMinimalFixture,
        )
        ..on(
          'GET',
          '/api/repos/$repoName/workflows',
          status: 200,
          body: workflowsEmptyFixture,
        )
        ..on(
          'GET',
          '/api/repos/$repoName/status',
          status: 200,
          body: repoStatusFullFixture,
        )
        ..on(
          'GET',
          '/api/repos/$repoName/workflows',
          status: 200,
          body: workflowsFixture,
        );
      final container = _makeContainer(t);
      final ws = await _connectSocket(container);

      container.listen(repoWorkflowsProvider(repoName), (_, _) {});
      await _pump();
      expect(
        container.read(repoWorkflowsProvider(repoName)).workflows,
        isEmpty,
      );

      final frame = EventFrame(
        session: '',
        event: workflowDoneEvent,
        extra: {'session': '', 'event': workflowDoneEvent, 'repo': repoName},
      );
      ws.addMessage(jsonEncode(frame.toJson()));
      await _pump();

      final state = container.read(repoWorkflowsProvider(repoName));
      expect(state.workflows, hasLength(1));
      expect(t.callCount('GET', '/api/repos/$repoName/workflows'), 2);
    });

    test(
      'a workflow_done event for a different repo does not trigger a re-fetch',
      () async {
        final t = FakeHttpTransport()
          ..on(
            'GET',
            '/api/repos/$repoName/status',
            status: 200,
            body: repoStatusMinimalFixture,
          )
          ..on(
            'GET',
            '/api/repos/$repoName/workflows',
            status: 200,
            body: workflowsEmptyFixture,
          );
        final container = _makeContainer(t);
        final ws = await _connectSocket(container);

        container.listen(repoWorkflowsProvider(repoName), (_, _) {});
        await _pump();
        expect(t.callCount('GET', '/api/repos/$repoName/workflows'), 1);

        final frame = EventFrame(
          session: '',
          event: workflowDoneEvent,
          extra: {
            'session': '',
            'event': workflowDoneEvent,
            'repo': 'some-other-repo',
          },
        );
        ws.addMessage(jsonEncode(frame.toJson()));
        await _pump();

        expect(t.callCount('GET', '/api/repos/$repoName/workflows'), 1);
      },
    );
  });
}
