/// Thin wrapper around the `flutter_markdown` dependency (declared in
/// `pubspec.yaml` by `BU.0.A`, first consumed here) — renders a markdown
/// string (currently just a repo's `handoff.md` body) inline within a
/// scrolling parent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Renders [data] as markdown, selectable, sized to its content (does not
/// scroll internally — callers embed it inside their own scroll view, as
/// `repo_detail_screen.dart` does).
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data});

  /// The raw markdown source to render.
  final String data;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      key: const ValueKey('markdown-view-body'),
      data: data,
      selectable: true,
    );
  }
}
