/// Session-detail screen — live pane view + send bar + quick-approve row.
///
/// Watches `pane_provider.dart`'s per-session [paneProvider] (REST-seeded,
/// WS-live pane buffer) for the routed [sessionName] and renders it via
/// `widgets/pane_view.dart`, with a free-text send bar above
/// `widgets/approve_button_row.dart`'s one-tap approve buttons below.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/events_provider.dart' show needsInputProvider;
import '../state/pane_provider.dart';
import '../state/sessions_provider.dart' show bastionApiProvider;
import '../widgets/approve_button_row.dart';
import '../widgets/pane_view.dart';

/// Live pane + quick-approve view for a single session.
class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.sessionName,
    this.embedded = false,
  });

  /// The session this screen is showing (route argument from
  /// `sessions_list_screen.dart`'s `sessionDetailRouteName`).
  final String sessionName;

  /// True when rendered inline as a [ResponsiveScaffold] detail pane
  /// (BU.4.A tablet split) rather than pushed as its own route. Suppresses
  /// the implied back button, since there is no route to pop back from.
  final bool embedded;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  @override
  void initState() {
    super.initState();
    _clearNeedsInput(widget.sessionName);
  }

  @override
  void didUpdateWidget(covariant SessionDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Embedded (tablet split-view) mode reuses this State object when the
    // operator taps a different session in the list — `initState` does not
    // run again, so the newly-selected session's badge must be cleared here.
    if (oldWidget.sessionName != widget.sessionName) {
      _clearNeedsInput(widget.sessionName);
    }
  }

  /// Drop the `needs_input` badge for [session] — the operator opening this
  /// screen counts as having viewed/acted on the prompt. Called from
  /// `initState`/`didUpdateWidget`, both of which run while Flutter's
  /// `BuildOwner` is mid-build for the whole tree being mounted/updated —
  /// mutating a [StateNotifier] at that point raises riverpod's
  /// modify-during-build error even though this widget's own `build` isn't
  /// the caller. Defer to the next frame via `addPostFrameCallback`, guarded
  /// by `mounted` since the frame callback can fire after this State is
  /// disposed (e.g. a fast session switch away before the frame lands).
  void _clearNeedsInput(String session) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(needsInputProvider.notifier).clear(session);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(paneProvider(widget.sessionName));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionName),
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: PaneView(lines: lines)),
          const Divider(height: 1),
          ApproveButtonRow(sessionName: widget.sessionName),
          const Divider(height: 1),
          _SendBar(sessionName: widget.sessionName),
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
    if (api == null) return;
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
