// Widget tests for LaunchSheet (`BU.12.E` task 6).
//
// Covers this task's acceptance criteria:
//   1. the workflow dropdown populates from a fake `GET /workflows`
//      registry and contains no hardcoded types — the test's registry
//      fixture is a deliberately unusual set of names that would never
//      appear in a hardcoded list, so a passing test proves the dropdown
//      really is registry-sourced rather than coincidentally matching one;
//   2. empty repo and empty spec slug each block submission client-side —
//      no request reaches the transport;
//   3. a successful (`202`) launch closes the sheet and surfaces the run
//      id (mirrors `showLaunchSheet`'s `Future<String?>` contract);
//   4. each `422` class renders its own message and marks the right
//      field/banner — `unknown workflow_type` / `unknown repo` /
//      `unknown spec_slug` mark their own [TextFormField]/dropdown via
//      `InputDecoration.errorText`; `policy resolution failed` /
//      `unresolvable target root` / an unrecognised `422` render as the
//      sheet-level `_GeneralErrorBanner` (`launch-sheet-general-error`);
//   5. the two `EngineWorkflowsUnavailable` causes (`notConfigured` /
//      `notMounted`) render distinguishable reasons in the workflow-type
//      field, not one generic disabled message;
//   6. a sentinel API key appears nowhere in the rendered tree, including
//      in any surfaced error text.
//
// `LaunchSheet` takes an already-constructed `EngineApi` for `launchRun`
// (mirrors `runs_screen.dart`'s ownership pattern — see the file's own
// doc comment) but sources its workflow-type dropdown from
// `engineWorkflowsProvider`, which builds its OWN client internally via
// `engineApiFactoryProvider` + `connectionProvider`/`readEngineKey()`. So
// this harness overrides `engineApiFactoryProvider` (wiring it to the same
// `FakeHttpTransport` as the passed-in `engine`) and `secureStorageProvider`
// (mirrors `run_control_test.dart`'s `_FakeSecureStorage`), then drives the
// sheet through the real `showLaunchSheet` modal-route helper so
// `Navigator.pop` on a `202` has a route to pop — mirrors
// `runs_screen_test.dart`'s "drive through the real public API" approach.

// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/launch_sheet.dart';
import 'package:bastion_ui/services/engine_api.dart';
import 'package:bastion_ui/state/connection_provider.dart'
    show secureStorageProvider;
import 'package:bastion_ui/state/engine_workflows_provider.dart'
    show engineApiFactoryProvider;
import 'package:bastion_ui/theme/app_theme.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

const _sentinelKey = 'sentinel-launch-sheet-do-not-leak-4d91c7';
const _kEngineKeyKey = 'bastion.auth.engine_key';

/// Mirrors `run_control_test.dart`/`settings_engine_key_test.dart`'s
/// `_FakeSecureStorage`.
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

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => {
    for (final e in store.entries)
      if (e.value != null) e.key: e.value!,
  };

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.clear();
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// A deliberately unusual registry fixture — nothing here could plausibly
/// be a hardcoded list already living in `lib/`, so a test that asserts
/// the dropdown shows exactly these proves the dropdown is registry-
/// sourced rather than coincidentally matching a real hardcoded list.
const _fixtureTypes = ['ZETA_PROBE', 'QUARK_SEED', 'ALPHA_MINT'];

/// Builds a `MaterialApp` with a single "open" button that launches
/// [LaunchSheet] via [showLaunchSheet], wired end to end to [transport]:
/// both the passed-in `engine:` (used for `launchRun`) and the
/// `engineWorkflowsProvider`'s internally-built client (via the overridden
/// [engineApiFactoryProvider]) share it, so one `FakeHttpTransport` can
/// answer both `GET /workflows` (registry) and `POST /events/` (launch).
Widget buildHarness({
  required FakeHttpTransport transport,
  String? engineKey = _sentinelKey,
}) {
  final storage = _FakeSecureStorage()..store[_kEngineKeyKey] = engineKey;
  final engine = EngineApi(
    host: 'test-host',
    port: 4317,
    key: engineKey,
    transport: transport,
  );

  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      engineApiFactoryProvider.overrideWithValue(
        ({required String host, required int port, required String? key}) =>
            EngineApi(host: host, port: port, key: key, transport: transport),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            key: const ValueKey('open-launch-sheet'),
            onPressed: () => showLaunchSheet(context, engine: engine),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

/// Registers the `GET /workflows` fixture registry and opens the sheet,
/// settling past the registry's async probe+fetch.
Future<void> openSheet(
  WidgetTester tester,
  FakeHttpTransport transport, {
  List<String> types = _fixtureTypes,
}) async {
  transport.on('GET', '/workflows', status: 200, body: types);
  await tester.pumpWidget(buildHarness(transport: transport));
  await tester.tap(find.byKey(const ValueKey('open-launch-sheet')));
  await tester.pumpAndSettle();
}

/// Fills the repo and spec-slug fields and selects a workflow type from
/// the fixture registry (defaults to its first entry).
Future<void> fillForm(
  WidgetTester tester, {
  String repo = 'bastion-ui',
  String specSlug = 'BU.12.E',
  String workflowType = 'ZETA_PROBE',
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('launch-sheet-repo-field')),
    repo,
  );
  await tester.enterText(
    find.byKey(const ValueKey('launch-sheet-spec-slug-field')),
    specSlug,
  );
  await tester.tap(
    find.byKey(const ValueKey('launch-sheet-workflow-dropdown')),
  );
  await tester.pumpAndSettle();
  // The dropdown menu renders the item text a second time (menu overlay);
  // `.last` picks the open menu's entry rather than the closed field.
  await tester.tap(find.text(workflowType).last);
  await tester.pumpAndSettle();
}

void main() {
  group('LaunchSheet — workflow registry', () {
    testWidgets('the dropdown populates from the live registry with no '
        'hardcoded types', (tester) async {
      final t = FakeHttpTransport();
      await openSheet(tester, t);

      await tester.tap(
        find.byKey(const ValueKey('launch-sheet-workflow-dropdown')),
      );
      await tester.pumpAndSettle();

      for (final type in _fixtureTypes) {
        expect(find.text(type), findsWidgets);
      }
      // No stray option beyond the three the fake registry returned —
      // every visible item text traces back to `_fixtureTypes`.
      final menuItemFinder = find.byType(DropdownMenuItem<String>);
      expect(menuItemFinder, findsNWidgets(_fixtureTypes.length));
    });
  });

  group('LaunchSheet — client-side validation', () {
    testWidgets('empty repo blocks submission client-side', (tester) async {
      final t = FakeHttpTransport();
      await openSheet(tester, t);

      await tester.enterText(
        find.byKey(const ValueKey('launch-sheet-spec-slug-field')),
        'BU.12.E',
      );
      await tester.tap(
        find.byKey(const ValueKey('launch-sheet-workflow-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_fixtureTypes[0]).last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Repo is required'), findsOneWidget);
      expect(t.callCount('POST', '/events/'), 0);
      // The sheet stays open.
      expect(find.byKey(const ValueKey('launch-sheet')), findsOneWidget);
    });

    testWidgets('empty spec slug blocks submission client-side', (
      tester,
    ) async {
      final t = FakeHttpTransport();
      await openSheet(tester, t);

      await tester.enterText(
        find.byKey(const ValueKey('launch-sheet-repo-field')),
        'bastion-ui',
      );
      await tester.tap(
        find.byKey(const ValueKey('launch-sheet-workflow-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_fixtureTypes[0]).last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Spec slug is required'), findsOneWidget);
      expect(t.callCount('POST', '/events/'), 0);
      expect(find.byKey(const ValueKey('launch-sheet')), findsOneWidget);
    });
  });

  group('LaunchSheet — successful launch', () {
    testWidgets('a 202 closes the sheet and surfaces the run id', (
      tester,
    ) async {
      final t = FakeHttpTransport();
      await openSheet(tester, t);
      t.on(
        'POST',
        '/events/',
        status: 202,
        body: {'run_id': 'run-launch-1', 'event_id': 'evt-launch-1'},
      );

      await fillForm(tester);
      await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('launch-sheet')), findsNothing);
      expect(find.textContaining('run-launch-1'), findsOneWidget);
    });
  });

  group('LaunchSheet — 422 rejections, each naming its field', () {
    testWidgets('unknown workflow_type marks the workflow-type field', (
      tester,
    ) async {
      final t = FakeHttpTransport();
      await openSheet(tester, t);
      t.on(
        'POST',
        '/events/',
        status: 422,
        body: {'error': 'unknown workflow_type', 'workflow_type': 'ZETA_PROBE'},
      );

      await fillForm(tester);
      await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unknown workflow type'), findsOneWidget);
      expect(find.textContaining('ZETA_PROBE'), findsWidgets);
      expect(find.byKey(const ValueKey('launch-sheet')), findsOneWidget);
    });

    testWidgets('unknown repo marks the repo field with the server message', (
      tester,
    ) async {
      final t = FakeHttpTransport();
      await openSheet(tester, t);
      t.on(
        'POST',
        '/events/',
        status: 422,
        body: {
          'error': 'unknown repo',
          'repo': 'no-such-repo',
          'message': 'no repo named no-such-repo is registered',
        },
      );

      await fillForm(tester, repo: 'no-such-repo');
      await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('no repo named no-such-repo is registered'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('launch-sheet')), findsOneWidget);
    });

    testWidgets(
      'unknown spec_slug marks the spec-slug field with the server message',
      (tester) async {
        final t = FakeHttpTransport();
        await openSheet(tester, t);
        t.on(
          'POST',
          '/events/',
          status: 422,
          body: {
            'error': 'unknown spec_slug',
            'spec_slug': 'NO.SUCH.SLUG',
            'message': 'no spec named NO.SUCH.SLUG exists',
          },
        );

        await fillForm(tester, specSlug: 'NO.SUCH.SLUG');
        await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
        await tester.pumpAndSettle();

        expect(find.text('no spec named NO.SUCH.SLUG exists'), findsOneWidget);
        expect(find.byKey(const ValueKey('launch-sheet')), findsOneWidget);
      },
    );

    testWidgets(
      'policy resolution failed renders as the sheet-level general banner',
      (tester) async {
        final t = FakeHttpTransport();
        await openSheet(tester, t);
        t.on(
          'POST',
          '/events/',
          status: 422,
          body: {
            'error': 'policy resolution failed',
            'message': 'no policy resolves for this workflow_type',
          },
        );

        await fillForm(tester);
        await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('launch-sheet-general-error')),
          findsOneWidget,
        );
        expect(
          find.text('no policy resolves for this workflow_type'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('launch-sheet')), findsOneWidget);
      },
    );

    testWidgets(
      'unresolvable target root renders as the sheet-level general banner',
      (tester) async {
        final t = FakeHttpTransport();
        await openSheet(tester, t);
        t.on(
          'POST',
          '/events/',
          status: 422,
          body: {
            'error': 'unresolvable target root',
            'message': 'no target root could be resolved',
          },
        );

        await fillForm(tester);
        await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('launch-sheet-general-error')),
          findsOneWidget,
        );
        expect(find.text('no target root could be resolved'), findsOneWidget);
      },
    );

    testWidgets(
      'an unrecognised 422 falls back to the general banner rendering the '
      'raw server text',
      (tester) async {
        final t = FakeHttpTransport();
        await openSheet(tester, t);
        t.on(
          'POST',
          '/events/',
          status: 422,
          body: {
            'error': 'some future rejection class the client does not know',
            'detail': 'added upstream after this client was written',
          },
        );

        await fillForm(tester);
        await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('launch-sheet-general-error')),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'some future rejection class the client does not know',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('LaunchSheet — workflow registry unavailable, two distinct causes', () {
    testWidgets('no engine key configured renders its own reason', (
      tester,
    ) async {
      final t = FakeHttpTransport();
      // No `GET /workflows` route registered — probeMount short-circuits
      // to `notConfigured` before any request when `key` is null.
      await tester.pumpWidget(buildHarness(transport: t, engineKey: null));
      await tester.tap(find.byKey(const ValueKey('open-launch-sheet')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('launch-sheet-workflow-unavailable')),
        findsOneWidget,
      );
      expect(
        find.textContaining('No engine key is configured'),
        findsOneWidget,
      );
    });

    testWidgets('engine not mounted renders a distinct reason', (tester) async {
      final t = FakeHttpTransport();
      t.on('GET', '/workflows', status: 404, body: 'not found');
      await tester.pumpWidget(buildHarness(transport: t));
      await tester.tap(find.byKey(const ValueKey('open-launch-sheet')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('launch-sheet-workflow-unavailable')),
        findsOneWidget,
      );
      expect(find.textContaining('not mounted'), findsOneWidget);
      // Distinguishable from the no-key reason above.
      expect(find.textContaining('No engine key is configured'), findsNothing);
    });
  });

  group('LaunchSheet — Standing Rule 7 (no key leak)', () {
    testWidgets('the sentinel key appears nowhere in the rendered tree, '
        'including surfaced error text', (tester) async {
      final t = FakeHttpTransport();
      await openSheet(tester, t);
      t.on(
        'POST',
        '/events/',
        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );

      await fillForm(tester);
      await tester.tap(find.byKey(const ValueKey('launch-sheet-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining(_sentinelKey), findsNothing);
    });
  });
}
