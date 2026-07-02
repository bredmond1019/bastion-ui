/// BastionUI entry point.
///
/// Boots a [ProviderScope]-wrapped [BastionApp] and routes to [HomeShell],
/// which owns the [BastionSocket] lifecycle and renders the connection banner
/// above the operator surface.
library;

// Hide Flutter's ConnectionState enum to avoid ambiguity with
// BastionUI's own ConnectionState from connection_provider.dart.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/session_detail_screen.dart';
import 'screens/sessions_list_screen.dart';
import 'screens/settings_screen.dart';
import 'services/bastion_api.dart';
import 'services/bastion_socket.dart';
import 'services/notifications.dart';
import 'state/connection_provider.dart';
import 'state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'widgets/connection_banner.dart';

Future<void> main() async {
  // Required before any platform-channel call (notifications init below)
  // runs ahead of runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the local-notifications plugin once at startup, then hand the
  // already-initialized service into the provider tree via an override so
  // `notificationWiringProvider` (wired up wherever the sessions/events
  // state is watched) can fire needs-input alerts without further setup.
  final notificationService = NotificationService();
  await notificationService.initialize();

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const BastionApp(),
    ),
  );
}

/// Root application widget.
class BastionApp extends StatelessWidget {
  const BastionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BastionUI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const HomeShell(),
      // Handles `sessionDetailRouteName(name)` pushes from
      // `SessionsListScreen`'s session cards.
      onGenerateRoute: (settings) {
        final name = settings.name;
        if (name != null && name.startsWith('/sessions/')) {
          final sessionName = Uri.decodeComponent(
            name.substring('/sessions/'.length),
          );
          return MaterialPageRoute<void>(
            builder: (_) => SessionDetailScreen(sessionName: sessionName),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}

/// App home shell.
///
/// Owns the [BastionSocket] lifecycle:
/// - On first frame, reads the persisted config + bearer token and opens the
///   socket (skips if host is not yet configured).
/// - Watches [connectionProvider] for config changes (e.g. after the user
///   saves new settings) and reconnects automatically.
/// - Calls [ConnectionNotifier.updateStatus] to bridge socket status into the
///   riverpod state that [ConnectionBanner] and other widgets watch.
/// - Disposes the socket cleanly on teardown.
///
/// Renders [ConnectionBanner] above a placeholder body, with a settings button
/// in the AppBar to navigate to [SettingsScreen].
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  BastionSocket? _socket;
  BastionApi? _api;

  @override
  void initState() {
    super.initState();
    // Defer socket init to the post-frame callback so providers are fully
    // initialised before we read them.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSocket());
  }

  /// Read persisted config + token and open the socket.
  ///
  /// No-op if the host has not been configured yet.
  Future<void> _initSocket() async {
    if (!mounted) return;
    final config = ref.read(connectionProvider).config;
    if (config.host.isEmpty) return;
    final token = await ref.read(connectionProvider.notifier).readToken() ?? '';
    if (!mounted) return;
    _openSocket(config, token);
  }

  /// Tear down any existing socket/API client and open new ones for
  /// [config]/[token].
  void _openSocket(ConnectionConfig config, String token) {
    _socket?.dispose();
    _api?.dispose();
    final socket = BastionSocket(
      host: config.host,
      port: config.port,
      token: token,
    );
    _socket = socket;
    _api = BastionApi(host: config.host, port: config.port, token: token);

    // Bridge socket status into connectionProvider so the banner and other
    // widgets that watch the provider update automatically.
    socket.statusStream.listen((status) {
      if (mounted) {
        ref.read(connectionProvider.notifier).updateStatus(status);
      }
    });

    socket.connect();
    // Rebuild so the session/pane/event provider tree gets overridden with
    // this live socket/API pair (see build()).
    if (mounted) setState(() {});
  }

  /// Called when the user saves new settings — reconnects with fresh config.
  Future<void> _reinitSocket(ConnectionConfig config) async {
    final token = await ref.read(connectionProvider.notifier).readToken() ?? '';
    if (!mounted) return;
    _openSocket(config, token);
  }

  @override
  void dispose() {
    _socket?.dispose();
    _api?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // React to config changes (e.g. after saving new server settings) and
    // reconnect the socket.  ref.listen in build() is idiomatic Riverpod for
    // ConsumerStatefulWidget — the subscription is re-registered each rebuild
    // but only fires once per actual state change.
    ref.listen<ConnectionState>(connectionProvider, (previous, next) {
      if (previous?.config != next.config && next.config.host.isNotEmpty) {
        _reinitSocket(next.config);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('BastionUI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Connection Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live connection-status banner — always visible at the top of the
          // operator surface so the user knows the tailnet link state.
          const ConnectionBanner(),
          Expanded(
            child: _socket == null || _api == null
                ? const Center(
                    child: Text('Configure a connection in Settings'),
                  )
                : ConnectedSessionsBody(socket: _socket!, api: _api!),
          ),
        ],
      ),
    );
  }
}

/// Session/pane/event provider tree, live once [socket]/[api] are connected.
///
/// A fresh nested [ProviderScope] overrides `bastionSocketProvider` and
/// `bastionApiProvider` with the concrete instances [HomeShell] owns, and
/// watches [notificationWiringProvider] to activate the needs-input ->
/// local-notification bridge for as long as this subtree is mounted.
///
/// Public (rather than `_`-private) so widget tests can pump it directly
/// with fake socket/API instances, without driving a real [BastionSocket]
/// connection through [HomeShell].
class ConnectedSessionsBody extends StatelessWidget {
  const ConnectedSessionsBody({
    super.key,
    required this.socket,
    required this.api,
  });

  final BastionSocket socket;
  final BastionApi api;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        bastionSocketProvider.overrideWithValue(socket),
        bastionApiProvider.overrideWithValue(api),
      ],
      child: const _NotificationWiredSessionsList(),
    );
  }
}

class _NotificationWiredSessionsList extends ConsumerWidget {
  const _NotificationWiredSessionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationWiringProvider);
    return const SessionsListScreen();
  }
}
