// Widget smoke test for the BastionUI root app shell.
//
// Verifies that the app boots, the ProviderScope is wired, the HomeShell
// renders with the AppBar + ConnectionBanner, and the settings route is
// reachable.

// Hide Flutter's ConnectionState enum to avoid ambiguity with
// BastionUI's own ConnectionState from connection_provider.dart.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/main.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/connection_banner.dart';

void main() {
  testWidgets('BastionApp boots with ProviderScope and renders HomeShell', (
    WidgetTester tester,
  ) async {
    // ProviderScope wraps BastionApp as it does in main().
    // HomeShell early-exits socket init because the default config has an
    // empty host — no platform-channel calls are made during this test.
    await tester.pumpWidget(const ProviderScope(child: BastionApp()));

    // The home scaffold and AppBar should render without error. The AppBar's
    // title is the bastiel lockup, not plain "BastionUI" text — see
    // test/widgets/home_shell_lockup_test.dart for why that placement is
    // pinned (it regressed once by living in ResponsiveScaffold instead).
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    expect(find.byType(BastielLockup), findsOneWidget);
    expect(find.text('BastionUI'), findsNothing);
  });

  testWidgets(
    'BastionApp supplies AppTheme.dark and renders dark unconditionally '
    '(BU.10.A Task 5)',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: BastionApp()));

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme, equals(AppTheme.dark));
      expect(app.darkTheme, isNull);
      expect(app.themeMode, equals(ThemeMode.dark));
      expect(app.theme!.brightness, equals(Brightness.dark));
    },
  );

  testWidgets('HomeShell renders ConnectionBanner and settings action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: BastionApp()));

    // Connection banner must be present in the widget tree.
    expect(find.byType(ConnectionBanner), findsOneWidget);

    // Settings icon button must be reachable.
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('settings button navigates to the SettingsScreen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: BastionApp()));

    // Tap the settings icon.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    // The settings screen AppBar title should appear.
    expect(find.text('Connection Settings'), findsOneWidget);
  });

  testWidgets(
    'ConnectionBanner shows Disconnected in initial unconfigured state',
    (WidgetTester tester) async {
      // Seed the provider with an explicit disconnected state so the test
      // does not depend on FlutterSecureStorage platform channels.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionProvider.overrideWith((_) => _DisconnectedNotifier()),
          ],
          child: const MaterialApp(home: Scaffold(body: ConnectionBanner())),
        ),
      );

      expect(find.text('Disconnected'), findsOneWidget);
    },
  );
}

/// Minimal notifier seeded to disconnected state — avoids FlutterSecureStorage
/// platform-channel calls in widget tests that need an explicit initial state.
class _DisconnectedNotifier extends StateNotifier<ConnectionState>
    implements ConnectionNotifier {
  _DisconnectedNotifier()
    : super(
        const ConnectionState(
          config: ConnectionConfig.defaultConfig,
          status: ConnectionStatus.disconnected,
        ),
      );

  @override
  Future<void> saveConfig({
    required String host,
    required int port,
    required String token,
  }) async {}

  @override
  Future<String?> readToken() async => null;

  @override
  void updateStatus(ConnectionStatus status) {
    state = state.copyWith(status: status);
  }
}
