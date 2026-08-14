/// Thin wrapper around the `flutter_markdown` dependency (declared in
/// `pubspec.yaml` by `BU.0.A`, first consumed here) — renders a markdown
/// string (currently just a repo's `handoff.md` body) inline within a
/// scrolling parent.
///
/// Re-skinned in `BU.10.C` task 5: maps headings onto [AppTypography]'s
/// heading family, body/list/quote text onto the body family, and code
/// spans/blocks onto the mono family on a [AppTokens.surfaceMuted] ground.
/// **Markdown body text is content, not a label** — no uppercase casing or
/// positive letter-spacing is applied to any of it, only to the mono code
/// treatment's font family itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Renders [data] as markdown, selectable, sized to its content (does not
/// scroll internally — callers embed it inside their own scroll view, as
/// `repo_detail_screen.dart` does).
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data});

  /// The raw markdown source to render.
  final String data;

  @override
  Widget build(BuildContext context) {
    final body = AppTypography.textTheme.bodyMedium?.copyWith(
      color: AppTokens.ink,
    );
    final code = AppTypography.mono.copyWith(color: AppTokens.accent2);

    return MarkdownBody(
      key: const ValueKey('markdown-view-body'),
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        a: body?.copyWith(color: AppTokens.primary),
        p: body,
        h1: AppTypography.textTheme.headlineSmall?.copyWith(
          color: AppTokens.ink,
        ),
        h2: AppTypography.textTheme.titleLarge?.copyWith(color: AppTokens.ink),
        h3: AppTypography.textTheme.titleMedium?.copyWith(color: AppTokens.ink),
        h4: body,
        h5: body,
        h6: body,
        em: body?.copyWith(fontStyle: FontStyle.italic),
        strong: body?.copyWith(fontWeight: FontWeight.w700),
        del: body?.copyWith(decoration: TextDecoration.lineThrough),
        blockquote: body?.copyWith(color: AppTokens.inkSoft),
        listBullet: body,
        tableHead: body?.copyWith(fontWeight: FontWeight.w700),
        tableBody: body,
        code: code,
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: AppTokens.surfaceMuted,
          border: Border.all(color: AppTokens.line, width: 1),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        blockquoteDecoration: BoxDecoration(
          color: AppTokens.surfaceMuted,
          border: Border(left: BorderSide(color: AppTokens.primary, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTokens.line, width: 1)),
        ),
      ),
    );
  }
}
