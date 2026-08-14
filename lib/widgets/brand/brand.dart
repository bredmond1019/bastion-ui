/// Barrel for BastionUI's six brand primitives (`BU.10.B`), ported from
/// `../bastion-web/components/ui/brand.tsx`.
///
/// Every task in this block appends its own export here — this file runs
/// under `/sdlc-task`, which executes sequentially on one branch with no
/// inter-task merge step, so a shared barrel is safe (see the block's
/// `tasks.md` Notes section).
library;

export 'panel_card.dart';
