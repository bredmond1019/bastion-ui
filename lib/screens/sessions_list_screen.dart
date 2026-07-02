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
import '../widgets/session_card.dart';

/// Route-name helper for a session's detail screen (`BU.1.A` Task 6).
///
/// Kept here (rather than importing a not-yet-existing detail screen) so
/// this file can be implemented and tested independently of Task 6; once
/// the detail screen exists it registers this route name.
String sessionDetailRouteName(String sessionName) => '/sessions/$sessionName';

/// Live sessions list — one card per session, sorted by name for a stable
/// display order.
class SessionsListScreen extends ConsumerWidget {
  const SessionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final needsInput = ref.watch(needsInputProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: sessions.isEmpty
          ? const Center(child: Text('No active sessions'))
          : _SessionsListView(sessions: sessions, needsInput: needsInput),
    );
  }
}

class _SessionsListView extends StatelessWidget {
  const _SessionsListView({required this.sessions, required this.needsInput});

  final List<SessionDto> sessions;
  final Set<String> needsInput;

  @override
  Widget build(BuildContext context) {
    final sorted = [...sessions]..sort((a, b) => a.name.compareTo(b.name));

    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final session = sorted[index];
        return SessionCard(
          key: ValueKey(session.name),
          session: session,
          needsInput: needsInput.contains(session.name),
          onTap: () => Navigator.of(
            context,
          ).pushNamed(sessionDetailRouteName(session.name)),
        );
      },
    );
  }
}
