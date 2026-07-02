/// Session-detail screen — live pane view + send bar + quick-approve row.
///
/// Watches `pane_provider.dart`'s per-session [paneProvider] (REST-seeded,
/// WS-live pane buffer) for the routed [sessionName] and renders it via
/// `widgets/pane_view.dart`, with a free-text send bar above
/// `widgets/approve_button_row.dart`'s one-tap approve buttons below.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/pane_provider.dart';
import '../state/sessions_provider.dart' show bastionApiProvider;
import '../widgets/approve_button_row.dart';
import '../widgets/pane_view.dart';

/// Live pane + quick-approve view for a single session.
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionName});

  /// The session this screen is showing (route argument from
  /// `sessions_list_screen.dart`'s `sessionDetailRouteName`).
  final String sessionName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(paneProvider(sessionName));

    return Scaffold(
      appBar: AppBar(title: Text(sessionName)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: PaneView(lines: lines)),
          const Divider(height: 1),
          ApproveButtonRow(sessionName: sessionName),
          const Divider(height: 1),
          _SendBar(sessionName: sessionName),
        ],
      ),
    );
  }
}

/// Free-text send bar — sends the typed literal keys (followed by `Enter`,
/// per serve-api's `send` semantics) to [sessionName] and clears the field.
class _SendBar extends ConsumerStatefulWidget {
  const _SendBar({required this.sessionName});

  final String sessionName;

  @override
  ConsumerState<_SendBar> createState() => _SendBarState();
}

class _SendBarState extends ConsumerState<_SendBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.isEmpty) return;
    final api = ref.read(bastionApiProvider);
    _controller.clear();
    try {
      await api.sendKeys(widget.sessionName, text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('send-bar-field'),
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Send keys…',
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              key: const ValueKey('send-bar-button'),
              icon: const Icon(Icons.send),
              tooltip: 'Send',
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}
