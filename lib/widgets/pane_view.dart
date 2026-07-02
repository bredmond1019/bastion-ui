/// Monospace, auto-scrolling plain-text render of a session's pane buffer.
///
/// Purely presentational: renders the `lines` it is given and does not read
/// any provider itself, so it stays easy to unit-test with plain constructor
/// arguments (mirrors `session_card.dart`'s style).
///
/// Auto-scrolls to the bottom whenever [lines] changes so the operator
/// always sees the most recent pane output without manual scrolling.
library;

import 'package:flutter/material.dart';

/// Read-only, monospace view of a pane buffer that auto-scrolls to the
/// bottom on every update.
class PaneView extends StatefulWidget {
  const PaneView({super.key, required this.lines});

  /// The current pane buffer, oldest line first (per `pane_provider.dart`).
  final List<String> lines;

  @override
  State<PaneView> createState() => _PaneViewState();
}

class _PaneViewState extends State<PaneView> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(covariant PaneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(8),
      child: Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.vertical,
          child: SelectableText(
            widget.lines.join('\n'),
            style: const TextStyle(
              fontFamily: 'monospace',
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
