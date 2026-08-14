/// Sessions-list screen — live session cards with a needs-input flag.
///
/// Watches `sessions_provider.dart`'s [sessionsProvider] (REST-seeded,
/// WS-live `List<SessionDto>`) and `events_provider.dart`'s
/// [needsInputProvider] (the set of session names currently flagged as
/// needing operator input), and renders one [SessionCard] per session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session_dto.dart';
import '../state/events_provider.dart';
import '../state/sessions_provider.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/brand/brand.dart';
import '../widgets/responsive_scaffold.dart';
import '../widgets/session_card.dart';
import 'session_detail_screen.dart';

/// Route-name helper for a session's detail screen (`BU.1.A` Task 6).
///
/// Kept here (rather than importing a not-yet-existing detail screen) so
/// this file can be implemented and tested independently of Task 6; once
/// the detail screen exists it registers this route name.
String sessionDetailRouteName(String sessionName) => '/sessions/$sessionName';

/// The session currently shown in the tablet split-view detail pane
/// (BU.4.A). Null on phone widths / before any selection. Only consulted
/// when `ResponsiveScaffold.isWide(context)` is true; phone taps still push
/// a route via [sessionDetailRouteName].
final selectedSessionProvider = StateProvider<String?>((ref) => null);

/// Live sessions list — one card per session, sorted by name for a stable
/// display order.
///
/// On tablet widths (`ResponsiveScaffold.isWide`) the list and the selected
/// session's detail render side-by-side via [ResponsiveScaffold]; on phone
/// widths tapping a card still pushes [SessionDetailScreen] as its own
/// route, unchanged from before BU.4.A.
class SessionsListScreen extends ConsumerWidget {
  const SessionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final needsInput = ref.watch(needsInputProvider);

    final isWide = ResponsiveScaffold.isWide(context);

    void onSessionTap(SessionDto session) {
      if (isWide) {
        ref.read(selectedSessionProvider.notifier).state = session.name;
      } else {
        Navigator.of(context).pushNamed(sessionDetailRouteName(session.name));
      }
    }

    final list = _SessionsListView(
      sessions: sessions,
      needsInput: needsInput,
      onTap: onSessionTap,
    );

    if (!isWide) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sessions')),
        body: list,
      );
    }

    final selected = ref.watch(selectedSessionProvider);
    final detail = selected == null
        ? const Center(child: Text('Select a session'))
        : SessionDetailScreen(sessionName: selected, embedded: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: ResponsiveScaffold(list: list, detail: detail),
    );
  }
}

/// The sessions-list body: one [Eyebrow] section header (budget rule: one
/// per section, never more), then either the empty state or the scrolling
/// list of [SessionCard]s. Kept as its own widget (rather than inlined into
/// [SessionsListScreen]'s build) so it renders identically for the phone
/// route and the tablet split-view rail.
class _SessionsListView extends StatelessWidget {
  const _SessionsListView({
    required this.sessions,
    required this.needsInput,
    required this.onTap,
  });

  final List<SessionDto> sessions;
  final Set<String> needsInput;
  final void Function(SessionDto session) onTap;

  @override
  Widget build(BuildContext context) {
    final sorted = [...sessions]..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Eyebrow(label: 'Sessions'),
        ),
        Expanded(
          child: sorted.isEmpty
              ? Center(
                  child: Text(
                    'No active sessions',
                    style: AppTypography.textTheme.bodyMedium?.copyWith(
                      color: AppTokens.inkFaint,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final session = sorted[index];
                    return SessionCard(
                      key: ValueKey(session.name),
                      session: session,
                      index: index,
                      needsInput: needsInput.contains(session.name),
                      onTap: () => onTap(session),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
