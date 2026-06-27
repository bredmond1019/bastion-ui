/// Live connection-status banner for the BastionUI app shell.
///
/// Watches [connectionProvider] for [ConnectionStatus] and renders a slim,
/// colour-coded indicator strip that updates in real time as the WebSocket
/// transitions between states.
///
/// Designed to sit at the top of [HomeShell] (below the AppBar) so every
/// operator surface always shows the current server link state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/connection_provider.dart';

/// A slim coloured banner that reflects the live [ConnectionStatus].
///
/// Reads [connectionProvider] from the nearest [ProviderScope].  No
/// business logic lives here — the banner is a pure projection of the
/// provider state.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionProvider).status;
    return _BannerStrip(status: status);
  }
}

// ---------------------------------------------------------------------------
// Internal presentational widget
// ---------------------------------------------------------------------------

class _BannerStrip extends StatelessWidget {
  const _BannerStrip({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _appearance(status);

    return ColoredBox(
      color: color,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps a [ConnectionStatus] to a (label, background colour, icon) triple.
  static (String, Color, IconData) _appearance(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.connected => (
        'Connected',
        const Color(0xFF388E3C), // green 700
        Icons.wifi,
      ),
      ConnectionStatus.connecting => (
        'Connecting…',
        const Color(0xFFF57C00), // orange 700
        Icons.wifi_find,
      ),
      ConnectionStatus.reconnecting => (
        'Reconnecting…',
        const Color(0xFFE65100), // deep orange 900
        Icons.wifi_tethering,
      ),
      ConnectionStatus.disconnected => (
        'Disconnected',
        const Color(0xFFC62828), // red 800
        Icons.wifi_off,
      ),
    };
  }
}
