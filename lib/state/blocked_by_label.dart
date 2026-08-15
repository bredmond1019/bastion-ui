/// Pure display-text mapping for `BlockedByDto` (`BU.13.C` task 2).
///
/// Turns one entry of `BoardBlockDto.blockedBy` into a human-readable
/// string for "what it waits on" in the restructured repo detail screen.
/// Pure Dart — no Flutter imports — so it is unit-testable without a
/// widget harness and reusable from any surface that needs to explain a
/// `blocked_by` entry.
///
/// Switches EXHAUSTIVELY over all five [BlockedByDto] variants with no
/// `default` case, so a future sixth variant fails to compile here rather
/// than silently falling through to a generic label.
library;

import 'package:bastion_ui/models/board_dto.dart';

/// Renders [dep] as a short, honest, human-readable description of what a
/// block is waiting on.
///
/// `UnknownBlockedByDto` — the degrade-not-throw case for an unrecognised
/// `blocked_by` shape (see `board_dto.dart`'s doc comment: the upstream
/// typeshare export is known-incomplete, so this WILL appear on the wire)
/// — never renders an empty string and never crashes. When the raw map
/// carries a `type` string, that type is named; otherwise a plain fallback
/// is used.
String blockedByLabel(BlockedByDto dep) {
  return switch (dep) {
    BlockDepDto(:final repo, :final id, :final what) =>
      what != null && what.isNotEmpty
          ? 'blocked by $repo/$id — $what'
          : 'blocked by $repo/$id',
    ExternalDepDto(:final what) => 'waiting on $what',
    OperatorDepDto(:final slug, :final exit, :final start, :final what) =>
      what != null && what.isNotEmpty
          ? 'waiting on operator session $slug ($start → $exit) — $what'
          : 'waiting on operator session $slug ($start → $exit)',
    ApprovalDepDto(:final slug, :final what, :final digest) =>
      'awaiting approval $slug — $what ($digest)',
    UnknownBlockedByDto(:final raw) => _unknownLabel(raw),
  };
}

/// Honest fallback for an [UnknownBlockedByDto]: names the raw `type` when
/// present, otherwise falls back to a plain, non-empty sentence. Never an
/// empty string, never a fabricated variant name.
String _unknownLabel(Map<String, dynamic> raw) {
  final type = raw['type'];
  if (type is String && type.isNotEmpty) {
    return 'waiting on an unrecognised dependency ($type)';
  }
  return 'waiting on an unrecognised dependency';
}
