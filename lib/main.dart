/// BastionUI entry point.
///
/// Boots a [ProviderScope]-wrapped [BastionApp] and routes to [HomeShell],
/// which owns the [BastionSocket] lifecycle and renders the connection banner
/// above the operator surface.
library;

// Hide Flutter's ConnectionState enum to avoid ambiguity with
// BastionUI's own ConnectionState from connection_provider.dart.
import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/frame.dart';
import 'screens/dashboard_screen.dart';
import 'screens/quick_actions_screen.dart';
import 'screens/repo_detail_screen.dart';
import 'screens/session_detail_screen.dart';
import 'screens/sessions_list_screen.dart';
import 'screens/settings_screen.dart';
import 'services/bastion_api.dart';
import 'services/bastion_socket.dart';
import 'services/notifications.dart';
import 'state/connection_provider.dart';
import 'state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'state/workflows_provider.dart' show workflowDoneEventsProvider;
import 'theme/app_theme.dart';
import 'widgets/brand/brand.dart';
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
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
      // Handles `sessionDetailRouteName(name)` pushes from
      // `SessionsListScreen`'s session cards and `repoDetailRouteName(name)`
      // pushes from `DashboardScreen`'s repo rows.
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
        if (name != null && name.startsWith('/repos/')) {
          final repoName = Uri.decodeComponent(
            name.substring('/repos/'.length),
          );
          return MaterialPageRoute<void>(
            builder: (_) => RepoDetailScreen(repoName: repoName),
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
    final api = BastionApi(host: config.host, port: config.port, token: token);
    _api = api;

    // Bridge socket status into connectionProvider so the banner and other
    // widgets that watch the provider update automatically.
    socket.statusStream.listen((status) {
      if (mounted) {
        ref.read(connectionProvider.notifier).updateStatus(status);
      }
    });

    socket.connect();
    // Publish onto the app's single root ProviderScope — visible everywhere
    // in the tree, including routes pushed onto the app's Navigator (which
    // sits above HomeShell, so a nested ProviderScope override here would
    // never be visible to pushed screens like SessionDetailScreen).
    ref.read(bastionSocketProvider.notifier).state = socket;
    ref.read(bastionApiProvider.notifier).state = api;
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
        // The bastiel lockup lives HERE, in HomeShell's own AppBar, because
        // this is the one app bar that is always visible — on every tab and
        // at every width. ResponsiveScaffold is used as a `body:` (see
        // sessions_list_screen.dart), so a lockup placed there would render
        // *below* this bar on the Sessions tab and not at all on Dashboard
        // or Actions. Same class of miss as BU.1.A: built, but not on the
        // path that actually renders.
        title: const BastielLockup(),
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
                : const _ConnectedBody(),
          ),
        ],
      ),
    );
  }
}

/// Tabbed body shown once [bastionSocketProvider]/[bastionApiProvider] are
/// live (see [_HomeShellState._openSocket]).
///
/// Watches both [notificationWiringProvider] (needs-input) and
/// [workflowDoneNotificationWiringProvider] (workflow-done) to activate the
/// local-notification bridges for as long as this subtree is mounted, then
/// renders a bottom-navigation tab bar switching between [SessionsListScreen]
/// and [DashboardScreen] (`BU.2.A` Task 7 — closes the loop `BU.1.A` left
/// implicit: a new screen existing and being unit-tested is not the same as
/// it being reachable from the running app). Reads the shared root-scope
/// providers directly (no nested `ProviderScope` override) so screens pushed
/// via the app's `Navigator` — an ancestor of this widget, not a descendant
/// — see the same live socket/API instances.
///
/// Also subscribes directly to [workflowDoneEventsProvider] to surface an
/// in-app [SnackBar] banner while foregrounded, in addition to (not instead
/// of) the local notification fired by [workflowDoneNotificationWiringProvider].
///
/// A third tab, [QuickActionsScreen], rounds out the bottom nav
/// (`BU.3.A` Task 6 — closes the loop `BU.1.A`/`BU.2.A` left implicit: a
/// screen existing and being unit-tested is not the same as it being
/// reachable from the running app).
class _ConnectedBody extends ConsumerStatefulWidget {
  const _ConnectedBody();

  @override
  ConsumerState<_ConnectedBody> createState() => _ConnectedBodyState();
}

class _ConnectedBodyState extends ConsumerState<_ConnectedBody> {
  static const _tabs = [
    SessionsListScreen(),
    DashboardScreen(),
    QuickActionsScreen(),
  ];

  int _tabIndex = 0;
  StreamSubscription<EventFrame>? _workflowDoneSub;

  @override
  void initState() {
    super.initState();
    // Defer to the post-frame callback, same pattern as
    // `_HomeShellState._initSocket` — providers (and the live socket) must
    // be fully available before this widget reads them.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _subscribeWorkflowDoneBanner(),
    );
  }

  void _subscribeWorkflowDoneBanner() {
    if (!mounted) return;
    final events = ref.read(workflowDoneEventsProvider);
    _workflowDoneSub = events.listen(_showWorkflowDoneBanner);
  }

  /// Shows a foreground [SnackBar] for a `workflow_done` event.
  ///
  /// Mirrors [workflowDoneNotificationWiringProvider]'s field-presence check
  /// — an event missing `repo`/`spec_slug`/`status` is ignored rather than
  /// rendering a malformed banner.
  void _showWorkflowDoneBanner(EventFrame frame) {
    if (!mounted) return;
    final repo = frame.extra['repo'] as String?;
    final specSlug = frame.extra['spec_slug'] as String?;
    final status = frame.extra['status'] as String?;
    if (repo == null || specSlug == null || status == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$repo — $specSlug is $status')));
  }

  @override
  void dispose() {
    _workflowDoneSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationWiringProvider);
    ref.watch(workflowDoneNotificationWiringProvider);

    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: 'Sessions'),
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(icon: Icon(Icons.flash_on), label: 'Actions'),
        ],
      ),
    );
  }
}
