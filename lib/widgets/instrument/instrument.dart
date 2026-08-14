/// Barrel for BastionUI's six data-display instrument primitives
/// (`BU.13.A`): `StatTile`, `LaneBar`, `SeverityRow`, `AgeChip`,
/// `Sparkline`, `GateCard`.
///
/// Each task in this block appends its own export here — this block runs
/// under `/sdlc-task`, sequentially on one branch with no inter-task merge
/// step, so a shared barrel is safe (see the block's `tasks.md` Notes).
///
/// These primitives are deliberately unreferenced by any screen when this
/// block lands — `BU.13.B`–`13.E` are the screens that consume them.
library;

export 'age_chip.dart';
export 'lane_bar.dart';
export 'severity_row.dart';
export 'sparkline.dart';
export 'stat_tile.dart';
