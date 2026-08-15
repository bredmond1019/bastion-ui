/// Service-level e2e test (`BU.13.E` task 6): drives the real
/// [runsProvider] / [RunsScreen] against a real `bastion serve` subprocess.
///
/// This is the runs-surface counterpart to `sessions_live_frame_e2e_test.dart`
/// / `reconnect_e2e_test.dart`: it proves two things a fake-socket unit test
/// cannot —
///
///   1. A real `subscribe(runs)` frame reaches the server and elicits a
///      real `event{run_stream_status}` reply (serve-api.md §14/§8), and the
///      real REST seed (`GET /api/runs`) round-trips through [RunsScreen]
///      into the honest no-engine empty state — never an error, never an
///      endless spinner (trap 3).
///   2. [RunsNotifier.dispose] (trap 1: unsubscribe on dispose) actually
///      reaches the server, not just that it compiles and sends *a* frame.
///      There is no server-side endpoint exposing per-topic subscriber
///      counts (`grep -n "subscriber count\|active_subscribers" ../bastion/
///      docs/serve-api.md` returns nothing), so the poller stopping when the
///      last subscriber leaves cannot be asserted directly from this
///      client. What IS directly observable:
///      `bastion_socket.dart`'s reconnect path replays `subscribe` for
///      every topic still in its `_activeTopics` registry
///      (`bastion_socket.dart:313-316`) — and `unsubscribe` removes the
///      topic from that registry (`bastion_socket.dart:374`). So after
///      disposing the provider, forcing a REAL reconnect
///      ([BastionServeHarness.restart]) and asserting NO fresh
///      `run_stream_status` arrives is real, live-server evidence that the
///      client-side half of trap 1 (unsubscribe sent, topic released, no
///      phantom resubscribe) held — see the second test below for the
///      explicit disclosure of what that does and does not prove.
///
/// ## The central "no user interaction" assertion — honestly NOT exercised
/// here
///
/// `bastion serve`'s `/api/runs` / `"runs"` topic project the embedded
/// engine's in-memory `LiveStateStore` (serve-api.md §14). That store is
/// populated only when the Section 18 engine routes are mounted, which
/// requires `DATABASE_URL` + `BASTION_ENGINE_API_KEY` at server start.
/// [BastionServeHarness] deliberately spawns `bastion serve` with NEITHER
/// set (`bastionServeHarnessChildEnvironment` is DB-free by design, matching
/// every other e2e test in this suite), and this repo's e2e seam has no
/// engine-mount variant and no engine-rs binary to drive one: `grep -rl
/// DATABASE_URL test/e2e/` turns up only doc comments, never an actual
/// spawn-with-engine path. **A run can therefore never appear in
/// `LiveStateStore` in this dev environment, so "a run started elsewhere
/// changes state on the phone with no user interaction" cannot be exercised
/// against a live server here** — exactly the condition the spec's Notes
/// section calls out ("assert the empty state honestly and RECORD that the
/// live-update half could not be exercised. Do not fake a pass."). This
/// file asserts the empty-state half for real and records this limitation
/// rather than replaying a synthetic `run_transition` frame and calling
/// that proof (a synthetic frame only proves the renderer works — that
/// coverage already exists in `runs_provider_test.dart` /
/// `runs_screen_test.dart`).
///
/// The entire body of each test runs inside [WidgetTester.runAsync],
/// following `briefing_e2e_test.dart`'s established pattern: a bare
/// `testWidgets` body executes inside a `FakeAsync` zone where real
/// `Timer`s never fire, which would stall indefinitely on this test's real
/// subprocess/socket/HTTP I/O. `TestWidgetsFlutterBinding` also installs a
/// global `HttpOverrides` that synthesizes a 400 for every `HttpClient`
/// request with no real network call — suspended for the duration and
/// restored afterward, exactly as `briefing_e2e_test.dart` does, since
/// `BastionApi`'s REST calls (through [runsProvider]'s REST seed) need a
/// real `HttpClient`.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`, which
/// requires a built `bastion` binary. Self-skips (via `markTestSkipped`)
/// when no `bastion` binary can be located.
@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:io' show HttpOverrides;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/screens/runs_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/state/runs_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('runs provider/screen e2e (BU.13.E task 6)', () {
    BastionServeHarness? harness;

    tearDown(() async {
      await harness?.stop();
      harness = null;
    });

    testWidgets(
      'subscribe reaches the server, GET /api/runs seeds empty, and the '
      'screen renders the honest no-engine empty state (never an error, '
      'never a spinner)',
      (tester) async {
        var skip = false;
        final previousHttpOverrides = HttpOverrides.current;
        HttpOverrides.global = null;

        try {
          await tester.runAsync(() async {
            harness = await BastionServeHarness.start();
            final h = harness;
            if (h == null) {
              if (bastionE2eRequireBinary()) {
                fail(
                  '$bastionE2eRequireEnvVar is set but no bastion binary '
                  'could be located (checked BASTION_BIN, '
                  '../bastion/target/release/bastion, '
                  '../bastion/target/debug/bastion) — build one with '
                  '`cargo build -p bastion` in ../bastion, or set '
                  'BASTION_BIN.',
                );
              }
              skip = true;
              return;
            }

            final api = BastionApi(host: h.host, port: h.port, token: h.token);
            final socket = BastionSocket(
              host: h.host,
              port: h.port,
              token: h.token,
            );
            final container = ProviderContainer();
            try {
              final connected = awaitStatus(
                socket,
                ConnectionStatus.connected,
                timeout: const Duration(seconds: 10),
              );
              socket.connect();
              await connected;
              expect(socket.status, ConnectionStatus.connected);

              container.read(bastionSocketProvider.notifier).state = socket;
              container.read(bastionApiProvider.notifier).state = api;

              // Register the run_stream_status collector BEFORE
              // constructing runsProvider (which sends the subscribe frame
              // in its constructor), mirroring the subscribe-before-listen
              // discipline documented on `collectFrames`.
              final streamStatus = collectFrames(
                socket,
                match: (frame) =>
                    frame is EventFrame && frame.event == 'run_stream_status',
                timeout: const Duration(seconds: 10),
              );

              // Building runsProvider constructs RunsNotifier, which sends
              // ClientFrames.subscribe(runsTopic) and seeds via GET
              // /api/runs.
              final listenerSub = container.listen(
                runsProvider,
                (previous, next) {},
                fireImmediately: true,
              );

              final statusFrames = await streamStatus;
              expect(
                statusFrames,
                hasLength(1),
                reason:
                    'a real subscribe(runs) frame should elicit exactly '
                    'one real event{run_stream_status} reply from the '
                    'server',
              );
              final statusFrame = statusFrames.single as EventFrame;
              // No DATABASE_URL/BASTION_ENGINE_API_KEY in this harness (see
              // this file's doc comment) — the engine is never mounted, so
              // LiveStateStore stays empty and `available` is honestly
              // false.
              expect(statusFrame.extra['available'], isFalse);

              // Real REST seed: no run has ever been tracked, so GET
              // /api/runs returns 200 [] and that is the whole (valid)
              // state.
              expect(container.read(runsProvider), isEmpty);

              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: container,
                  child: const MaterialApp(home: RunsScreen()),
                ),
              );
              await tester.pump();

              expect(
                find.byKey(const ValueKey('runs-empty-state')),
                findsOneWidget,
                reason:
                    'a 200 [] response must render the explanatory empty '
                    'state, never an error and never an endless spinner',
              );
              expect(find.byType(CircularProgressIndicator), findsNothing);
              expect(find.textContaining('Could not load'), findsNothing);
              expect(tester.takeException(), isNull);

              listenerSub.close();
            } finally {
              container.dispose();
              await socket.dispose();
              api.dispose();
            }
          });
        } finally {
          HttpOverrides.global = previousHttpOverrides;
        }

        if (skip) {
          markTestSkipped(
            'no bastion binary found (checked BASTION_BIN, '
            '../bastion/target/release/bastion, '
            '../bastion/target/debug/bastion) — skipping runs '
            'provider/screen e2e (set $bastionE2eRequireEnvVar=1 to make '
            'this a hard failure instead)',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    testWidgets(
      'disposing the runs provider releases the "runs" subscription: a '
      'real post-dispose reconnect replays no fresh run_stream_status',
      (tester) async {
        var skip = false;
        final previousHttpOverrides = HttpOverrides.current;
        HttpOverrides.global = null;

        try {
          await tester.runAsync(() async {
            harness = await BastionServeHarness.start();
            final h = harness;
            if (h == null) {
              skip = true;
              return;
            }

            final api = BastionApi(host: h.host, port: h.port, token: h.token);
            final socket = BastionSocket(
              host: h.host,
              port: h.port,
              token: h.token,
            );
            final container = ProviderContainer();
            var socketDisposed = false;
            try {
              final connected = awaitStatus(
                socket,
                ConnectionStatus.connected,
                timeout: const Duration(seconds: 10),
              );
              socket.connect();
              await connected;

              container.read(bastionSocketProvider.notifier).state = socket;
              container.read(bastionApiProvider.notifier).state = api;

              final firstStatus = collectFrames(
                socket,
                match: (frame) =>
                    frame is EventFrame && frame.event == 'run_stream_status',
                timeout: const Duration(seconds: 10),
              );
              final listenerSub = container.listen(
                runsProvider,
                (previous, next) {},
                fireImmediately: true,
              );
              // Confirms the subscribe really reached the server before we
              // assert anything about its release.
              await firstStatus;
              listenerSub.close();

              // --- Trap 1: unsubscribe on dispose ---
              // Disposing the container disposes the (non-autoDispose)
              // StateNotifierProvider's RunsNotifier automatically
              // (runs_provider.dart's doc comment), which sends
              // ClientFrames.unsubscribe(runsTopic) and removes "runs"
              // from BastionSocket's `_activeTopics` replay registry
              // (bastion_socket.dart:374).
              container.dispose();

              // What this proves, and what it does not: there is no server
              // route exposing the runs-poller's live subscriber count, so
              // "the server's poller stopped" is not directly observable
              // from this client (recorded honestly rather than asserted).
              // What IS observable: a real reconnect only replays
              // `subscribe` for topics still present in `_activeTopics`
              // (bastion_socket.dart:313-316). If dispose() had NOT sent
              // unsubscribe (or had not cleared the registry), this
              // reconnect would immediately replay subscribe(runs) and a
              // fresh run_stream_status would land in the window below.
              // Its absence is real, live-server evidence that the
              // unsubscribe was sent and took effect — not merely that
              // dispose() ran without throwing.
              final postReconnectStatus = collectFrames(
                socket,
                match: (frame) =>
                    frame is EventFrame && frame.event == 'run_stream_status',
                timeout: const Duration(seconds: 5),
              );
              final reconnected = awaitStatus(
                socket,
                ConnectionStatus.connected,
                timeout: const Duration(seconds: 20),
              );
              await h.restart();
              await reconnected;

              await expectLater(
                postReconnectStatus,
                throwsA(isA<TimeoutException>()),
                reason:
                    'a run_stream_status frame arriving after this '
                    'reconnect would mean "runs" was still in the '
                    'active-topic replay registry — i.e. dispose() did '
                    'not actually release the subscription',
              );

              await socket.dispose();
              socketDisposed = true;
            } finally {
              if (!socketDisposed) {
                await socket.dispose();
              }
              api.dispose();
            }
          });
        } finally {
          HttpOverrides.global = previousHttpOverrides;
        }

        if (skip) {
          markTestSkipped(
            'no bastion binary found — skipping runs dispose/unsubscribe '
            'e2e (set $bastionE2eRequireEnvVar=1 to make this a hard '
            'failure instead)',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
