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

import '../screens/settings_screen.dart';
import '../state/connection_provider.dart';
import '../theme/status_tones.dart';
import '../theme/tokens.dart';

/// A slim coloured banner that reflects the live [ConnectionStatus].
///
/// Reads [connectionProvider] from the nearest [ProviderScope].  No
/// business logic lives here — the banner is a pure projection of the
/// provider state, plus a tap affordance that opens [SettingsScreen] (every
/// state is tappable, not only the error ones, so the operator can always
/// jump to the connection config from wherever the banner is showing).
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
    final tones = context.statusTones;
    final appearance = _appearance(status, tones);
    // The banner is a solid full-bleed strip (unlike a StatusTone chip's
    // low-alpha fill), so it uses the tone's foreground hue as a saturated
    // background with AppTokens.paper text/icons for contrast — the same
    // "onPrimary" pattern AppTheme.dark uses for its ColorScheme.
    final background = appearance.tone.foreground;
    final foreground = AppTokens.paper;

    return Material(
      color: background,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          );
        },
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(appearance.icon, color: foreground, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        appearance.label,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: foreground),
                      ),
                      if (appearance.subtitle != null)
                        Text(
                          appearance.subtitle!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: foreground),
                        ),
                    ],
                  ),
                ),
                if (appearance.showAction)
                  Icon(Icons.chevron_right, color: foreground, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Maps a [ConnectionStatus] to its full visual + copy appearance, reading
  /// its colour triplet from [tones] (the ambient [StatusTones]) rather than
  /// a hardcoded literal.
  static _BannerAppearance _appearance(
    ConnectionStatus status,
    StatusTones tones,
  ) {
    return switch (status) {
      ConnectionStatus.connected => _BannerAppearance(
        label: 'Connected',
        subtitle: null,
        tone: tones.active,
        icon: Icons.wifi,
        showAction: false,
      ),
      ConnectionStatus.connecting => _BannerAppearance(
        label: 'Connecting…',
        subtitle: null,
        tone: tones.warning,
        icon: Icons.wifi_find,
        showAction: false,
      ),
      ConnectionStatus.reconnecting => _BannerAppearance(
        label: 'Reconnecting…',
        subtitle: 'Trying to restore the link to bastion serve',
        tone: tones.warning,
        icon: Icons.wifi_tethering,
        showAction: false,
      ),
      ConnectionStatus.disconnected => _BannerAppearance(
        label: 'Disconnected',
        subtitle: 'Tap to check your server settings',
        tone: tones.danger,
        icon: Icons.wifi_off,
        showAction: true,
      ),
    };
  }
}

/// Full visual appearance for a given [ConnectionStatus]: label, optional
/// subtitle copy, [StatusTone] triplet, leading icon, and whether the
/// trailing settings affordance icon is shown.
class _BannerAppearance {
  const _BannerAppearance({
    required this.label,
    required this.subtitle,
    required this.tone,
    required this.icon,
    required this.showAction,
  });

  final String label;
  final String? subtitle;
  final StatusTone tone;
  final IconData icon;
  final bool showAction;
}
