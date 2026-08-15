// Widget tests for QuickActionsScreen + CommandInvokeSheet.
//
// Overrides `bastionApiProvider` (fake HTTP transport), `sessionsProvider`
// (fake StateNotifier, mirrors `sessions_list_test.dart`'s override style),
// and `secureStorageProvider` (in-memory fake, mirrors
// `commands_provider_test.dart`) so these tests exercise the real palette +
// invoke-sheet wiring without any platform channels or network I/O.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/screens/quick_actions_screen.dart';
import 'package:bastion_ui/screens/sessions_list_screen.dart'
    show sessionDetailRouteName;
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/state/commands_provider.dart';
import 'package:bastion_ui/state/connection_provider.dart'
    show secureStorageProvider;
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, sessionsProvider, SessionsNotifier;
import 'package:bastion_ui/widgets/brand/brand.dart';
import 'package:bastion_ui/widgets/command_invoke_sheet.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSessionsNotifier extends StateNotifier<List<SessionDto>>
    implements SessionsNotifier {
  _FakeSessionsNotifier(super.state);
}

class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String?> _store = {};

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
    _store[key] = value;
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
    return _store[key];
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildScreen({
  required FakeHttpTransport httpTransport,
  List<SessionDto> sessions = const [],
  FlutterSecureStorage? storage,
}) {
  final api = BastionApi(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transport: httpTransport,
  );

  return ProviderScope(
    overrides: [
      bastionApiProvider.overrideWith((ref) => api),
      sessionsProvider.overrideWith((ref) => _FakeSessionsNotifier(sessions)),
      secureStorageProvider.overrideWithValue(storage ?? _FakeSecureStorage()),
    ],
    child: MaterialApp(
      home: const QuickActionsScreen(),
      onGenerateRoute: (settings) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('detail:${settings.name}')),
        );
      },
    ),
  );
}

void main() {
  group('QuickActionsScreen', () {
    testWidgets('renders palette entries with defaults on first run', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreen(httpTransport: FakeHttpTransport()));
      await tester.pumpAndSettle();

      for (final entry in defaultPaletteCommands) {
        expect(find.text(entry.label), findsOneWidget);
      }
    });

    testWidgets('renders brand primitives — PanelCard, HeadingRule, IconTile', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreen(httpTransport: FakeHttpTransport()));
      await tester.pumpAndSettle();

      expect(find.byType(PanelCard), findsWidgets);
      expect(find.byType(HeadingRule), findsOneWidget);
      expect(find.byType(GradientTopBar), findsWidgets);
      expect(find.byType(IconTile), findsWidgets);
    });

    testWidgets('invoke sheet shows the Eyebrow label and the fired command', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreen(httpTransport: FakeHttpTransport()));
      await tester.pumpAndSettle();

      final fired = defaultPaletteCommands[0];
      await tester.tap(find.text(fired.label));
      await tester.pumpAndSettle();

      expect(find.byType(Eyebrow), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CommandInvokeSheet),
          matching: find.text(fired.command),
        ),
        findsOneWidget,
      );
    });

    testWidgets('add creates a new persisted entry', (tester) async {
      final storage = _FakeSecureStorage();
      await tester.pumpWidget(
        _buildScreen(httpTransport: FakeHttpTransport(), storage: storage),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('command-add-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('command-dialog-label')),
        'My Custom',
      );
      await tester.enterText(
        find.byKey(const Key('command-dialog-command')),
        '/custom',
      );
      await tester.tap(find.byKey(const Key('command-dialog-save')));
      await tester.pumpAndSettle();

      expect(find.text('My Custom'), findsOneWidget);

      // Persisted: reload from the same storage produces the edited list.
      final raw = await storage.read(key: 'bastion.commands.list');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as List;
      expect(
        decoded.any(
          (e) => e['label'] == 'My Custom' && e['command'] == '/custom',
        ),
        isTrue,
      );
    });

    testWidgets('edit updates an existing entry', (tester) async {
      await tester.pumpWidget(_buildScreen(httpTransport: FakeHttpTransport()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('command-edit-0')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('command-dialog-label')),
        'Renamed',
      );
      await tester.tap(find.byKey(const Key('command-dialog-save')));
      await tester.pumpAndSettle();

      expect(find.text('Renamed'), findsOneWidget);
      expect(find.text(defaultPaletteCommands[0].label), findsNothing);
    });

    testWidgets('delete removes an entry', (tester) async {
      await tester.pumpWidget(_buildScreen(httpTransport: FakeHttpTransport()));
      await tester.pumpAndSettle();

      final removedLabel = defaultPaletteCommands[0].label;
      await tester.tap(find.byKey(const Key('command-delete-0')));
      await tester.pumpAndSettle();

      expect(find.text(removedLabel), findsNothing);
    });

    testWidgets(
      'inject requires a session — invoke button disabled until one is picked',
      (tester) async {
        const sessions = [SessionDto(name: 'alpha', state: 'running')];
        await tester.pumpWidget(
          _buildScreen(httpTransport: FakeHttpTransport(), sessions: sessions),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(defaultPaletteCommands[0].label));
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('command-invoke-button')),
        );
        expect(button.onPressed, isNull);

        await tester.tap(find.byKey(const Key('command-invoke-session')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('alpha').last);
        await tester.pumpAndSettle();

        final buttonAfter = tester.widget<FilledButton>(
          find.byKey(const Key('command-invoke-button')),
        );
        expect(buttonAfter.onPressed, isNotNull);
      },
    );

    testWidgets(
      'spawn requires a non-empty name — invoke button disabled until set',
      (tester) async {
        await tester.pumpWidget(
          _buildScreen(httpTransport: FakeHttpTransport()),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(defaultPaletteCommands[0].label));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('command-invoke-mode-toggle')).last,
        );
        // Tap the "Spawn" segment explicitly.
        await tester.tap(find.text('Spawn'));
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('command-invoke-button')),
        );
        expect(button.onPressed, isNull);

        await tester.enterText(
          find.byKey(const Key('command-invoke-name')),
          'new-session',
        );
        await tester.pumpAndSettle();

        final buttonAfter = tester.widget<FilledButton>(
          find.byKey(const Key('command-invoke-button')),
        );
        expect(buttonAfter.onPressed, isNotNull);
      },
    );

    testWidgets(
      'invoke sends the right CommandRequest and success navigates to the '
      'returned session id',
      (tester) async {
        const sessions = [SessionDto(name: 'alpha', state: 'running')];
        final httpTransport = FakeHttpTransport();
        httpTransport.on(
          'POST',
          '/api/actions/command',
          status: 200,
          body: {'session': 'alpha'},
        );

        await tester.pumpWidget(
          _buildScreen(httpTransport: httpTransport, sessions: sessions),
        );
        await tester.pumpAndSettle();

        final fired = defaultPaletteCommands[0];
        await tester.tap(find.text(fired.label));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('command-invoke-session')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('alpha').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('command-invoke-button')));
        await tester.pumpAndSettle();

        final call = httpTransport.calls.single;
        expect(call.method, 'POST');
        expect(call.url, endsWith('/api/actions/command'));
        final sentBody = jsonDecode(call.body!) as Map<String, dynamic>;
        expect(sentBody['mode'], 'inject');
        expect(sentBody['session'], 'alpha');
        expect(sentBody['command'], fired.command);
        expect(sentBody.containsKey('dir'), isFalse);
        expect(sentBody.containsKey('model'), isFalse);

        expect(
          find.text('detail:${sessionDetailRouteName('alpha')}'),
          findsOneWidget,
        );
      },
    );

    testWidgets('an ApiError surfaces the error and does NOT navigate', (
      tester,
    ) async {
      const sessions = [SessionDto(name: 'alpha', state: 'running')];
      final httpTransport = FakeHttpTransport();
      httpTransport.on(
        'POST',
        '/api/actions/command',
        status: 404,
        body: {'code': 'C002', 'error': 'unknown session'},
      );

      await tester.pumpWidget(
        _buildScreen(httpTransport: httpTransport, sessions: sessions),
      );
      await tester.pumpAndSettle();

      final fired = defaultPaletteCommands[0];
      await tester.tap(find.text(fired.label));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('command-invoke-session')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('alpha').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('command-invoke-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('command-invoke-error')), findsOneWidget);
      // Still on the invoke sheet — no detail route was pushed.
      expect(find.byType(CommandInvokeSheet), findsOneWidget);
      expect(find.textContaining('detail:'), findsNothing);
    });
  });
}
