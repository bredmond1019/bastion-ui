// Widget tests for ConnectionBanner.
//
// Verifies that the banner renders the correct label and visual indicator for
// every ConnectionStatus value, and that it updates in response to provider
// state changes.

// Hide Flutter's ConnectionState enum to avoid ambiguity with
// BastionUI's own ConnectionState from connection_provider.dart.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/settings_screen.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/widgets/connection_banner.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds the [ConnectionBanner] inside a [ProviderScope] that overrides
/// [connectionProvider] with a state seeded to [status].
Widget _buildBanner(ConnectionStatus status) {
  final overrideState = ConnectionState(
    config: ConnectionConfig.defaultConfig,
    status: status,
  );

  return ProviderScope(
    overrides: [
      connectionProvider.overrideWith(
        (ref) => _FakeConnectionNotifier(overrideState),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: ConnectionBanner())),
  );
}

/// A minimal [ConnectionNotifier] that holds a fixed state and never touches
/// [FlutterSecureStorage] — safe to use in unit/widget tests.
class _FakeConnectionNotifier extends StateNotifier<ConnectionState>
    implements ConnectionNotifier {
  _FakeConnectionNotifier(super.state);

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConnectionBanner', () {
    testWidgets('shows "Connected" for ConnectionStatus.connected', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBanner(ConnectionStatus.connected));
      expect(find.text('Connected'), findsOneWidget);
      expect(find.byIcon(Icons.wifi), findsOneWidget);
    });

    testWidgets('shows "Connecting…" for ConnectionStatus.connecting', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBanner(ConnectionStatus.connecting));
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_find), findsOneWidget);
    });

    testWidgets('shows "Reconnecting…" for ConnectionStatus.reconnecting', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBanner(ConnectionStatus.reconnecting));
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);
      // Reconnecting has distinct explanatory copy (not just the disconnected
      // call-to-action) and does not show the chevron affordance icon.
      expect(
        find.text('Trying to restore the link to bastion serve'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('shows "Disconnected" for ConnectionStatus.disconnected', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBanner(ConnectionStatus.disconnected));
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      // Disconnected is the only state with a call-to-action + chevron icon.
      expect(find.text('Tap to check your server settings'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets(
      'connecting and connected states show no subtitle or chevron icon',
      (tester) async {
        await tester.pumpWidget(_buildBanner(ConnectionStatus.connecting));
        expect(find.byIcon(Icons.chevron_right), findsNothing);

        await tester.pumpWidget(_buildBanner(ConnectionStatus.connected));
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      },
    );

    testWidgets('tapping the banner opens SettingsScreen', (tester) async {
      await tester.pumpWidget(_buildBanner(ConnectionStatus.disconnected));

      expect(find.byType(SettingsScreen), findsNothing);

      await tester.tap(find.byType(ConnectionBanner));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets(
      'tapping the banner in a connected state also opens SettingsScreen',
      (tester) async {
        await tester.pumpWidget(_buildBanner(ConnectionStatus.connected));

        await tester.tap(find.byType(ConnectionBanner));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
      },
    );

    testWidgets('each status resolves its colour from the ambient StatusTones '
        'extension, not a literal hex value', (tester) async {
      final tones = StatusTones.dark;
      final expected = {
        ConnectionStatus.connected: tones.active,
        ConnectionStatus.connecting: tones.warning,
        ConnectionStatus.reconnecting: tones.warning,
        ConnectionStatus.disconnected: tones.danger,
      };

      for (final entry in expected.entries) {
        // Remount cleanly each iteration: pumping a new ProviderScope
        // override in place can otherwise leave the previous provider
        // state alive across pumps.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(_buildBanner(entry.key));
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(ConnectionBanner),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, entry.value.foreground);
      }
    });

    testWidgets('banner updates when provider state changes', (tester) async {
      // Start in disconnected state.
      final notifier = _FakeConnectionNotifier(
        const ConnectionState(
          config: ConnectionConfig.defaultConfig,
          status: ConnectionStatus.disconnected,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionProvider.overrideWith((_) => notifier)],
          child: const MaterialApp(home: Scaffold(body: ConnectionBanner())),
        ),
      );

      expect(find.text('Disconnected'), findsOneWidget);

      // Transition to connected.
      notifier.updateStatus(ConnectionStatus.connected);
      await tester.pump();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Disconnected'), findsNothing);
    });
  });
}
