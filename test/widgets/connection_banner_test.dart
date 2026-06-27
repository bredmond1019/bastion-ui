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

import 'package:bastion_ui/state/connection_provider.dart';
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
    });

    testWidgets('shows "Disconnected" for ConnectionStatus.disconnected', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBanner(ConnectionStatus.disconnected));
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
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
