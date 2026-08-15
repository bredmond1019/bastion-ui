---
type: Log
title: BastionUI Development Log
description: Chronological log of work completed for BastionUI.
timestamp: "2026-08-14T11:52:00Z"
---

# Log — BastionUI

*Append-only working log. One dated entry per session. Newest entries at the top.*

---

## [run: 2026-08-15]

`13.E-live-runs` (`BU.13.E` — Live runs, read + runs WebSocket topic) closed — all 7 tasks passed,
end-of-run review **PASS**. Task 1 added `run_dto.dart` (`RunSummaryDto`/`RunStateDto`/
`NodeTransitionDto`/`RunUsageDto`) mirroring serve-api.md §14, including the v0.22 `repo` field.
Task 2 added `BastionApi.getRuns()`/`getRun(id)` (bearer-auth only). Task 3 wired a minimal
`RunsScreen` as `HomeShell`'s fifth bottom-nav tab. Task 4 added `runs_provider.dart`: REST-seeds
the run list then keeps it live via the bearer-authed `runs` WS topic, applying `run_transition`
events (suspended stays live, `terminal:true` removes the run), unsubscribing on dispose. Task 5
built out `RunsScreen` with a live list (status badge + `AgeChip`), a node-transition drill-in per
run, and an honest empty state for `GET /api/runs` returning `[]`. Task 6 added
`test/e2e/runs_ws_e2e_test.dart` proving a real subscribe reaches `bastion serve` and that
dispose()'s unsubscribe holds on reconnect; the dev harness never mounts the engine, so the
live-update half of the AC is honestly exercised via the empty-state path rather than faked. Task 7
validated the full spec: format/analyze/test all pass (803 tests, up from 772), all 5 nav-touching
test files unchanged and passing, no `X-API-Key` usage added. `state.json` block `BU.13.E` flipped
to closed. Next: `BU.13.F` — states, motion and density pass.

```
29c8d9c docs: update docs for 13.E-live-runs
317ca81 feat: implement 13.E-live-runs-task6
eaca2b0 feat: implement 13.E-live-runs-task5
1e2aad1 feat: implement 13.E-live-runs-task4
dc92260 feat: implement 13.E-live-runs-task3
1fd6ea4 feat: implement 13.E-live-runs-task2
8239ae3 feat: implement 13.E-live-runs-task1
e0895bf BU.13.D — Portfolio (Dashboard rebuilt as a ranked instrument) (#7)
```

`13.D-portfolio-instrument` (`BU.13.D` — Portfolio, Dashboard rebuilt as a ranked instrument)
closed — all 7 tasks passed, end-of-run review **PASS**. Task 1 added `last_touched` to
`BoardBlockDto` as a nullable `DateTime` (parsed via `DateTime.tryParse`, degrading to null rather
than throwing on a malformed wire string), documented to mean "never worked" unconditionally at
the single-block level. Task 2 added `lib/state/portfolio_ranking.dart`: a pure, Flutter-free
`rankPortfolio()` tiering repos into needsAttention/active/quiet from a sealed `RepoRecency`
(`Known` vs `NeverWorked`) so a never-worked repo can never be mistaken for stale, with 18 new
unit tests. Task 3 rebuilt `DashboardScreen` onto `rankPortfolio()`, replacing the old flat
`reposProvider` list with Eyebrow-headed tiers of `SeverityRow`s carrying a `LaneBar`
(done/now/blocked/next); reused the existing `briefingBoardProvider` rather than adding a second
board fetch. Task 4 added an `AgeChip`/"not started" chip and a 7-day activity `Sparkline` per
repo row, derived client-side from real per-block `last_touched` timestamps (omitted entirely for
repos with no activity in-window). Task 5 collapsed the quiet tier to a tap-to-expand summary row
and fixed the `StatusPill` tone mapping so an active/RUNNING repo reads louder than an idle/ON
TRACK one, per D4 constraint 3. Task 6 added a real-server e2e test
(`test/e2e/portfolio_e2e_test.dart`, self-skips without a `bastion` binary), which surfaced a
legitimate real-fleet case (`business` landing in needs-attention while never-worked, via an open
gate) that sharpened the test's guard rather than exposing a bug. Task 7 confirmed the full
validation suite: `dart format` clean, `flutter analyze` clean, `flutter test --exclude-tags e2e`
773 passed (+30 over the pre-spec baseline of 743), and confirmed the sole `DateTime.now()` call
sits in `initState` (captured once, threaded down), not `build()` or `portfolio_ranking.dart`.
Next: `BU.13.E` (Live runs — read + runs WebSocket topic).

```
d4ca2ef docs: update docs for 13.D-portfolio-instrument
652c7f5 feat: implement 13.D-portfolio-instrument-task6
d01c12b feat: implement 13.D-portfolio-instrument-task5
a48390e feat: implement 13.D-portfolio-instrument-task4
3b98550 feat: implement 13.D-portfolio-instrument-task3
68f1e8f feat: implement 13.D-portfolio-instrument-task2
6f63003 feat: implement 13.D-portfolio-instrument-task1
```

---

## [run: 2026-08-14]

`13.B-briefing-screen` (`BU.13.B` — The Briefing, new home surface) closed — all 9 tasks passed,
end-of-run review **PASS**. Task 1 built the pure `BriefingViewModel`/`BriefingSectionState`
ranking layer (null-safe descending sort for operator gates by `dependent_count`, needs-input
sessions by idle time, blocked blocks by `age_days`). Task 2 landed `BriefingScreen` as the app's
first bottom-nav tab, ahead of Sessions/Dashboard/Actions. Task 3 added `briefing_provider.dart`
composing `getBoard(graph: true)`, `getAttention`, and the existing `sessionsProvider` into the
view model via independently-fetching sections, with `refreshFailedBriefingSections` re-fetching
only errored sections. Task 4 wired the three-stat header (needs-you/blocked/running, em-dash on
section error). Tasks 5–6 built the three ranked lanes (gates + needs-input sessions, blocked
blocks, live runs) as `GateCard`/`SeverityRow` instrument primitives, each with its own inline
error state (retry) and empty state, isolated from the other lanes. Task 7 resolved the
"Act"/retry vs. active-status-pill color ambiguity by using a structural filled/borderless-vs-bordered
channel instead of hue, both on `AppTokens.accent2`. Task 8 added a real-server e2e test
(self-skips without a `bastion` binary) cross-checking header counts against independent
board/attention/sessions fetches and confirming `getBoard(graph: true)` populates blast radius;
ran it green against a freshly rebuilt `bastion` binary. Task 9 confirmed the full validation
suite: `dart format` clean, `flutter analyze` clean, `flutter test --exclude-tags e2e` 707 passed
(+51 over the pre-spec baseline of 656). Notable decision: `getBoard(graph: true)` is paid on
every board load rather than fetched separately, recorded in the spec's Notes. Next: `BU.13.C`
(Repo detail, restructured).

```
2d9449d docs: update docs for 13.B-briefing-screen
bbf6f56 feat: implement 13.B-briefing-screen-task8
77a2261 feat: implement 13.B-briefing-screen-task7
0f12406 feat: implement 13.B-briefing-screen-task6
6d6ea14 feat: implement 13.B-briefing-screen-task5
856f27f feat: implement 13.B-briefing-screen-task4
ee642bb feat: implement 13.B-briefing-screen-task3
ed8bb1d feat: implement 13.B-briefing-screen-task2
6877a54 feat: implement 13.B-briefing-screen-task1
```

## [run: 2026-08-14]

`BU.10.C` (re-skin existing screens + brand app icon) closed — all 10 tasks passed, end-of-run
review **PASS**. Tasks 1–5 re-skinned every screen and shared widget onto `AppTokens`/
`AppTypography`/the `lib/widgets/brand/` primitives: `ResponsiveScaffold`/`ConnectionBanner`/
`StatusBadge` (task 1), `SessionsListScreen`/`SessionCard` (task 2), `SessionDetailScreen`/
`ApproveButtonRow` with `PaneView` wrapped in a `PanelCard` (task 3), the dashboard repo rows/
`RepoDetailScreen`/`WorkflowProgress` (task 4), and `QuickActionsScreen`/`SettingsScreen`/
`CommandInvokeSheet`/`MarkdownView` (task 5). Task 6 added `brand_coverage_test.dart` confirming
every re-skinned screen renders at least one brand primitive, and a mechanical sweep found no
remaining stock-Material/hex-literal leakage. Task 7 replaced the launcher icon with a generated
bastiel gem-mark adaptive icon (faceted diamond in brand hues on `AppTokens.paper`), regenerating
all Android mipmap/drawable densities via `flutter_launcher_icons`. Task 8 fixed a formatting-only
Patrol test-bundle failure. Task 9 captured a fresh post-brand `visual_smoke/runs/2026-08-14_155931/`
baseline (10 screens) against a real `bastion serve` on a Pixel_9 emulator, diffed screen-by-screen
against the pre-brand baseline. Task 10 ran the full gating suite (format/analyze/test, all green)
and — since task 8's worklog hadn't actually captured live Patrol device output — re-ran the Patrol
smoke test live to produce the missing evidence for the spec's un-gateable acceptance criteria.
Phase 10 (brand system) is now fully closed. Notable decisions: the tablet split-rail grounds list
on `AppTokens.surface`/detail on `AppTokens.paper` (no separate nav-rail widget exists yet); agent
state maps onto `StatusPillTone` as working→inProgress/idle→onTrack/blocked→blocked; `ListTile` was
dropped in favor of a plain `Row` for dashboard/quick-action rows to avoid width-overflow inside a
`StatusPill`-bearing row at tablet width. Next: Phase 11 (`BU.11.A` — serve-api v0.30 contract
layer) or Phase 12, whichever the operator prioritizes next; the two operator gates
(`bastion-ui-brand-signoff`, `bastion-ui-engine-api-key`) remain ahead of `BU.11.B`/`BU.12.A`.

```
696342d feat: implement 10.C-reskin-screens-icon-task9
137e90e feat: implement 10.C-reskin-screens-icon-task8
5e233a8 feat: implement 10.C-reskin-screens-icon-task7
c0d120d feat: implement 10.C-reskin-screens-icon-task6
467d802 feat: implement 10.C-reskin-screens-icon-task5
113e2bc feat: implement 10.C-reskin-screens-icon-task4
dbe067d feat: implement 10.C-reskin-screens-icon-task3
c761eea feat: implement 10.C-reskin-screens-icon-task2
```

## [run: 2026-08-14]

`BU.10.A` (design tokens + dark-only theme foundation) closed — all 7 tasks passed on the first
attempt, end-of-run review **PASS**. Task 1 vendored the three OFL brand type families (Inter,
Source Sans 3, JetBrains Mono) as variable-font TTFs via `pubspec.yaml` (not the `google_fonts`
package, per the tailnet-only constraint). Task 2 added `lib/theme/tokens.dart` (`AppTokens`:
cool-aurora palette, radius ladder, glow values, alpha helper). Task 3 added the `StatusTones`
`ThemeExtension` (six semantic tones — neutral/info/active/success/warning/danger — each with
foreground/background/border) with safe `ThemeData`/`BuildContext` fallback accessors. Task 4 added
`lib/theme/typography.dart` (`AppTypography.textTheme`: Inter for display/headline/title, Source
Sans 3 for body/label, JetBrains Mono for mono/labels). Task 5 replaced `ColorScheme.fromSeed` with
a single explicit `AppTheme.dark` built from tokens/tones/typography, wired `main.dart` to
`ThemeMode.dark` and dropped `darkTheme`/`ThemeMode.system`. Task 6 migrated the four widgets that
hardcoded `Color(0x...)` literals (`connection_banner`, `session_card`, `status_badge`,
`pane_view`) to read `StatusTones`/`AppTokens` instead, adding a guard test enforcing zero such
literals remain outside `lib/theme/`. Task 7 validated the full gating suite with no further code
changes. Notable decisions: `AppTheme.dark` is a cached `static final` (not a getter) because
`NavigationBarThemeData`'s `WidgetStateProperty.resolveWith` closures break `==` equality across
rebuilt `ThemeData` instances; `ConnectionBanner` and the emphasized agent-state chip use a tone's
solid `foreground` as background with `AppTokens.paper` text (rather than the tone's own
low-alpha `background`/`border`) for contrast on a full-bleed strip. `test/widget_test.dart` was
updated (outside task 5's listed files) because it referenced the now-deleted
`AppTheme.light`/`ThemeMode.system` wiring. Next: `BU.10.B` (brand primitive widget kit, ported
from `bastion-web/components/ui/brand.tsx`).

```
957dbb5 docs: update docs for 10.A-design-tokens-theme
7c55986 feat: implement 10.A-design-tokens-theme-task6
e19ad5c feat: implement 10.A-design-tokens-theme-task5
f242d6d feat: implement 10.A-design-tokens-theme-task4
8c9cb6c feat: implement 10.A-design-tokens-theme-task3
570ae94 feat: implement 10.A-design-tokens-theme-task2
6b7e2a5 feat: implement 10.A-design-tokens-theme-task1
660dec6 feat: implement ticket-needs-input-badge-clear-task3
```

---

## [2026-08-14] (3)

### Phases 10–12 registered — brand + operator surfaces roadmap, Wave 0 and 5 specs

- **What:** A four-way audit (this app · `bastion serve` · `bastion-web` · the bastiel/cockpit
  brand) measured two gaps: the app targets serve-api **v0.5** against a **v0.30** server and calls
  **12 of 26** routes, and it carries no brand at all (`lib/theme/app_theme.dart` was 28 lines of
  `ColorScheme.fromSeed(Colors.blueGrey)` on `ThemeMode.system`, rendering stock Material *light*).
  Authored **Phase 10** (brand system: tokens → primitives → re-skin), **Phase 11** (operator read
  surfaces: v0.30 contract layer → briefing+attention → docs reader) and **Phase 12** (engine
  control: client+`X-API-Key` → runs → live `runs` WS topic → pause/resume/abort → launch) as 11
  block sections in `master-plan.md`, and registered 11 blocks + 2 tickets in `state.json`. Retired
  `BU.5.A` to `wontfix` (Phase 12 decomposes it) and **dropped the deferred serve-api v1.0.0 pin**
  that had blocked `BU.5.A`/`BU.6.A` since 2026-07-23. Created roadmap
  `bastion-ui-brand-and-surfaces` at HQ (roadmap.md + lane-bastion-ui.txt + lane-log.jsonl +
  context.md), with two operator gates modelled as typed `depends_on` edges. Then wrote the five
  specs whose decomposition does not depend on a predecessor's concrete output:
  `ticket-session-agent-state`, `ticket-dashboard-now-render`, `ticket-needs-input-badge-clear`,
  `10.A-design-tokens-theme`, `11.A-serve-api-v030-contract-layer` (23 tasks total).
- **Why:** The app had drifted 25 contract versions behind the server while waiting on a v1.0.0
  freeze that was never going to arrive — nine contract amendments landed in August alone. And every
  screen added before the brand lands is a screen that has to be retreaded afterwards, so the
  operator chose brand first. The audit also surfaced two real bugs worth ticketing: the Dashboard
  renders a literal `[]` on every repo card, and `NeedsInputNotifier.clear()` is implemented, tested,
  and called from nowhere — so the needs-input badge never clears.
- **Refs:** commits `3559d4e1` (Wave 0), `49049f54` (specs + context);
  `planning/roadmaps/bastion-ui-brand-and-surfaces/` at HQ; `planning/handoff.md`. The other nine
  specs are deliberately ungenerated — they need real token names, constructors and DTO fields to
  spec without inventing them (context.md §9).

---

## [2026-08-14] (2)

### Patrol wired into the harness as a non-gating, manual-only check

- **What:** Registered `patrol-visual-smoke` in `planning/harness.json`'s `validation.checks[]`
  (`gates: false`), driven by a new `scripts/run_patrol_smoke.sh`. The script self-skips (exit 0)
  when there's no attached Android device/emulator or no built `bastion` binary; otherwise it
  starts a real `bastion serve` on `:4317` (reusing one already running there), runs
  `patrol_test/smoke_test.dart` against it, and tears the server down on exit if it started it.
  Verified end-to-end: ran clean (12/12 steps pass, server auto-started and cleanly torn down) and
  self-skip verified separately (no device → `SKIPPED`, exit 0). Deliberately **not** wired through
  `harness.json`'s `uiTest` field — that's `playwright-cli`/web-specific mechanism baked into
  `sdlc-run.js`'s UI Test stage, not a generic hook, so extending it for Patrol would mean editing
  the engine for stack reasons (against this project's own standing rule). Recorded as
  `planning/decisions/D3-patrol-non-gating-harness-check.md`. Resolved and removed the
  `patrol-harness-adoption-undecided` carryover entry.
- **Why:** User asked for parity with how Playwright is wired into the harness for Next.js apps,
  then clarified it must never run automatically on every task (development-time cost) — `gates:
  false` under this project's `testDepth=fast` default means the SDLC engines never invoke it
  per-task or on the terminal reconcile pass; it only runs when a human or agent calls it
  deliberately, same trust level as the existing `e2e-serve-contract` check.
- **Refs:** `scripts/run_patrol_smoke.sh`, `planning/harness.json`,
  `planning/decisions/D3-patrol-non-gating-harness-check.md`.

## [2026-08-14]

### Patrol installed + first visual-smoke baseline captured

- **What:** Installed Patrol (`patrol_cli` 4.7.0 + `patrol` 4.9.0 packages) and got a real smoke
  test running on an Android emulator (`Pixel_9`) against a live `bastion serve` — no mocks, real
  tmux sessions, real repo registry. Added the required Android wiring
  (`android/app/build.gradle.kts` instrumentation runner/orchestrator/desugaring,
  `android/app/src/androidTest/java/com/bastionui/bastion_ui/MainActivityTest.java`). Wrote
  `patrol_test/smoke_test.dart` — connects via Settings, asserts Sessions/Dashboard render real
  backend data, opens a session and a repo, opens the Quick Actions add-command dialog; 12/12
  steps pass. Since Patrol 4.x's binding has no screenshot API, built a separate
  `adb exec-out screencap`-driven visual tour and a new `visual_smoke/` convention for keeping
  those screenshots as a durable, deliberate, disk-only record — timestamped run folders,
  `manifest.md` tracked in git, PNGs git-ignored so routine test runs never pile them up.
  `visual_smoke/runs/2026-08-14_061003/` is the first baseline (10 screens).
- **Why:** User wants agent-driven visual/functional testing of the Flutter app (the mobile
  equivalent of Playwright for web), plus a way to compare UI state across runs over time without
  every routine `/sdlc-task`/`/sdlc-flow` pass silently accumulating screenshots.
- **Refs:** `patrol_test/smoke_test.dart`, `visual_smoke/README.md`; ad-hoc session, no
  `planning/<concept>/` spec dir or `state.json` block (same precedent as `BU.9.x`, 2026-07-19).

## [2026-07-23]

### BU.4.A — PR #3 merged to main

- **What:** PR #3 (`4.A-polish-v0.1-flow` → `main`, theme polish + responsive scaffold +
  connection banner + app icon) merged via `gh pr merge 3 --merge --delete-branch`; local `main`
  fast-forwarded to the merge commit `8652e3a`, branch deleted, working tree clean. The `sdlc-flow`
  run behind the PR executed 7 tasks (all passed first attempt), one consolidated end-of-run review
  (PASS, no findings), and a docs patch (`docs/architecture.md`, `docs/pages.md`) before opening the
  PR. Changed files: `lib/theme/app_theme.dart` (new), `lib/widgets/responsive_scaffold.dart` (new),
  `lib/widgets/connection_banner.dart`, `lib/screens/session_detail_screen.dart`,
  `lib/screens/sessions_list_screen.dart`, `lib/main.dart`, `assets/icon/app_icon.png` (new app
  icon), plus tests (`test/app_icon_test.dart`, `test/theme/app_theme_test.dart`,
  `test/widgets/responsive_test.dart`, `test/widgets/connection_banner_test.dart`,
  `test/widgets/sessions_list_test.dart`, `test/main_wiring_test.dart`, `test/widget_test.dart`),
  `pubspec.yaml`/`pubspec.lock`.
- **Why:** Closes out the `4.A-polish-v0.1` spec — the scoped-down, contract-free half of `BU.4.A`
  (theme, responsive layout, reconnect UX, app icon) — by landing its branch-train PR on `main`,
  matching the merge-based workflow used for prior blocks (e.g. PR #2).
- **Refs:** PR #3 (`4.A-polish-v0.1-flow`); spec at `planning/4.A-polish-v0.1/`; see the same-day
  entry below for the flow's task-level narrative and the deferred v1.0.0 pin/tag follow-up.

### BU.4.A closed — polish (theme, responsive layout, reconnect UX, app icon)

- **What:** Ran `sdlc-flow` for `4.A-polish-v0.1` across 7 tasks (all passed first attempt),
  end-of-run review PASS. Task 1 added `lib/theme/app_theme.dart` (Material 3 light/dark `ThemeData`,
  blueGrey seed). Task 2 added `lib/widgets/responsive_scaffold.dart` (single-pane below a 720dp
  breakpoint, list+detail split at/above it). Task 3 gave `ConnectionBanner` distinct per-status copy
  and a tap affordance to `SettingsScreen` in every connection state. Task 4 wired
  `SessionsListScreen`/`SessionDetailScreen` through `ResponsiveScaffold` via a new
  `selectedSessionProvider`, embedding the detail pane on tablet widths while phones keep
  push-navigation. Task 5 replaced the default Flutter launcher icon with a blueGrey "B" monogram
  badge generated via `flutter_launcher_icons` across all mipmap densities. Task 6 wired
  `MaterialApp` in `lib/main.dart` to `AppTheme.light`/`AppTheme.dark` + `ThemeMode.system` and added
  a regression test guarding against a double-rendered detail pane at tablet width. Task 7 was
  validation-only (dart format/flutter analyze/flutter test all clean; no code changes needed). The
  spec was deliberately **scoped down** from the master-plan block: the serve-api v1.0.0 pin and the
  v0.1 git tag are **deferred**, since upstream `bastion/docs/serve-api.md` is still v0.5 and Block K
  (BA.11.F) has not shipped — pinning now would fabricate a contract version (Standing Rule 6).
- **Why:** Polish work (dark theme, tablet-aware layout, clearer reconnect UX, a real app icon) was
  ready and contract-free, so it shipped now rather than waiting on the unrelated upstream freeze;
  the pin+tag half is left as an explicit follow-up once `bastion` Block K lands.
- **Refs:** commits `d47c943`..`4a39821` (tasks 1–6) + `47b69ea` (docs); spec at
  `planning/4.A-polish-v0.1/`.
- Next: pick up the deferred serve-api v1.0.0 pin + v0.1 tag once `bastion` Block K (BA.11.F) ships,
  or start `BU.5.A` (Engine workflow screen) once that unblocks it.

```
47b69ea docs: update docs for 4.A-polish-v0.1
4a39821 feat: implement 4.A-polish-v0.1-task6
ba4c8e1 feat: implement 4.A-polish-v0.1-task5
e52ea04 feat: implement 4.A-polish-v0.1-task4
1e1f5a9 feat: implement 4.A-polish-v0.1-task3
d1cd3f6 feat: implement 4.A-polish-v0.1-task2
d47c943 feat: implement 4.A-polish-v0.1-task1
e2340df docs: log e2e coverage round 2 (BU.9.A-E) + upstream §12.3 fix
```

## [2026-07-19]

### E2E coverage round 2 (BU.9.A–E) + upstream §12.3 fix

- **What:** Added four real-server e2e tests closing coverage gaps a self-audit found in
  already-shipped behaviours (previously only fake/unit-tested), plus supporting harness infra in
  `test/e2e/`. New files: `sessions_live_frame_e2e_test.dart` (BU.9.B — sessions provider live-frame),
  `command_inject_e2e_test.dart` (BU.9.C — inject-into-live-session success),
  `reconnect_e2e_test.dart` (BU.9.D — reconnect resilience), `error_frame_e2e_test.dart` (BU.9.E —
  error/`WS_ERR` frame decode); infra (BU.9.A) added `restart()` + `collectFrames()`/`awaitStatus()`
  helpers to `bastion_serve_harness.dart` + `e2e_support.dart`. Running the suite against a live
  `bastion serve` caught a real **upstream** bug: bastion's `is_unknown_session()` didn't match tmux
  3.6b's "can't find pane" string, so inject-into-unknown-session returned **500 instead of the
  documented serve-api §12.3 404/C002**. Fixed in the `bastion` repo
  (`src/serve/handlers/sessions.rs` + unit test, commit `a562043`) and made the BU.8.B inject test
  deterministic (guard session). Gates: bastion-ui green (313 tests), full e2e suite **11/11** against
  the real server, bastion **1346 tests** green. `needs_input` remains the one deliberate deferred gap
  (needs a real blocked Claude TUI).
- **Why:** The app is heavily agent-built, so real-server e2e is the safety net against the fake-test
  drift that agent authorship invites. A coverage audit found four already-shipped behaviours only
  fake-tested; closing them with live-server tests is what surfaced the upstream §12.3 mapping bug —
  proof the safety net earns its keep.
- **Refs:** bastion-ui `c56ae48`; bastion `a562043`. Implemented directly (no `planning/<concept>/`
  plan dir or `state.json` blocks — per user direction).

### BU.8.B closed: workflow_done event push + spawn-mode command round-trip e2e

- **What:** Ran `/close-out` for block `BU.8.B` (workflow_done event push + spawn-mode command
  round-trip e2e). All 5 `sdlc-task` tasks passed on the first attempt, driven on branch `main`
  in-place (no worktree): commits `060e8c6`, `eb770e0`, `2e6b5cf`, `6016f99` built out
  `test/e2e/workflow_events_e2e_test.dart` plus supporting changes in
  `test/e2e/bastion_serve_harness.dart`, `test/e2e/e2e_support.dart`, and
  `test/e2e/e2e_support_test.dart` (589 lines added across 4 files, all under `test/e2e/` — no
  `lib/` source changed). Close-out validation: `dart format` clean, `flutter analyze` clean,
  `flutter test --exclude-tags e2e` green (313 tests), emoji gate OK. No coverage gaps (the diff
  was entirely test infra). `/code-review low` returned no findings — all changed hunks were test
  files, out of scope for review at that level. `/update-docs --patch` found no STALE/MISSING —
  the e2e harness is already documented via `planning/harness.json`'s `_comment`, consistent with
  prior e2e blocks (BU.7.A–BU.8.A) which also got no per-file doc entries. Removed the now-resolved
  `planning/state.json` carryover entry `ba0a-workflow-done-push-now-live` (its `clears_when`
  condition, "BU.8.B part (1) e2e lands", was met this session). With BU.8.B closed, all Phase
  0–3/7/8 blocks and the ad-hoc `plan-client-contract-fixes` blocks (`BU.0.A-ccf`, `BU.0.B-ccf`,
  `BU.0.C-ccf`) are now Done/closed. Critical path returns to `BU.4.A` (polish + v0.1 tag, pins
  serve-api v1.0.0 / bastion Block K), which is next and not yet started. `planning/handoff.md`
  was rewritten to reflect this.
- **Why:** Closing out the BU.8.B e2e block — the last item in the ad-hoc Phase 7/8 e2e-coverage
  plan — so the project can cleanly return to the phase-ordered master-plan sequence at `BU.4.A`.
- **Refs:** commits `060e8c6`, `eb770e0`, `2e6b5cf`, `6016f99`; block `BU.8.B`

## [2026-07-18]

### PR #2 merged + main divergence reconciled

- **What:** Merged PR #2 (`plan-client-contract-fixes` — reconnect resilience: resubscribe +
  re-seed + fatal 401) into `main` via `gh pr merge 2 --squash --delete-branch` (merged
  2026-07-19T00:43:44Z, squash commit `8e3c40f`). Local `main` had diverged from `origin/main`
  (local `main` carried unpushed commits, including `12911d4`, ahead of the same stale base point
  `389c1df` that the PR's squash-merge landed on top of on `origin/main`). Reconciled with
  `git merge origin/main --no-edit`, which produced one conflict in `log.md` (both sides had
  appended entries to the top of today's section) — resolved by keeping both entries
  (origin/main's `plan-client-contract-fixes` entry followed by local main's pre-existing
  `BU.8.A` entry), committed as merge commit `bd761d0`. Reverified the gating suite green after
  the merge (`dart format --output=none --set-exit-if-changed .` clean, `flutter analyze` — no
  issues, `flutter test --exclude-tags e2e` — 303 tests passed) and pushed
  (`8e3c40f..bd761d0 main -> main`).
- **Why:** Close out the `plan-client-contract-fixes` sdlc-flow run (block `BU.0.A-ccf`) by
  landing its PR on `main`, and repair the stale-`origin/main` divergence uncovered in the
  process so local and remote `main` agree before further work continues.
- **Refs:** PR https://github.com/bredmond1019/bastion-ui/pull/2

### BU.0.A-ccf closed: Reconnect resilience — resubscribe + re-seed + fatal 401

- **What:** Closed out block `BU.0.A-ccf` (`plan-client-contract-fixes`, Phase 0 — ad-hoc client
  contract fixes, D34 seam). Ran via `/sdlc-flow` on branch `plan-client-contract-fixes-flow`; all
  5 tasks passed on the first attempt, end-of-run review verdict **PASS**:
  - task1 — `lib/services/bastion_socket.dart`: `BastionSocket` now tracks active
    subscribe/unsubscribe topics via the existing `send()` path (a `Set<String>` registry) and
    replays a `subscribe` frame for every still-active topic on each successful reconnect (never on
    the first connect), so live WS streams survive a transient tailnet drop without a manual
    navigate-away/back. New test `test/services/reconnect_resubscribe_test.dart`.
  - task2 — same file: a handshake-time `WebSocketException` thrown by `transport.ready` (e.g. a
    401 `/ws` upgrade rejection whose message carries no numeric status code) is now detected as
    fatal auth via a new handshake-path-only `_isFatalHandshakeError`, stopping reconnect, while the
    existing substring-based `_isAuthError` on the in-stream `onError` path is unchanged and
    genuinely transient handshake failures still back off normally.
  - task3 — `lib/state/sessions_provider.dart`: `SessionsNotifier` subscribes to the socket's
    `statusStream` and re-runs `_seed()` on a reconnect transition (into `connected` after the
    first connect, tracked via an `_everConnected` flag seeded from the socket's status at listener
    attach time), preserving the `_sawWsSnapshot` precedence guard and cancelling the status
    subscription in `dispose()`.
  - task4 — `lib/state/pane_provider.dart`: mirrored the same reconnect re-seed pattern in
    `PaneNotifier`, preserving the `_sawWsFrame`/`_lastSeq` precedence guards.
  - task5 — validation-only; gating suite reconfirmed green with no code changes.
  Close-out: gating suite green (`dart format` clean, `flutter analyze` clean, `flutter test
  --exclude-tags e2e` green), end-of-run review PASS (no findings), doc patch applied to
  `docs/api-reference.md` and `docs/architecture.md`.
- **Why:** A 2026-07-18 four-agent client⇄server contract audit found three genuine client-side
  defects; this block fixes the highest-severity one — live streams going silent after any
  reconnect — plus the infinite-reconnect-loop-on-bad-token defect, both scoped to
  `bastion_socket.dart` and the two REST-seeding notifiers. The other two blocks in the same ad-hoc
  plan (`BU.0.B-ccf` — decouple repo status + workflows fetch, `BU.0.C-ccf` — bump the serve-api pin
  label v0.4→v0.5) are unaffected (disjoint files, no `depends_on`) and remain open for a future
  pass.
- **Next:** `BU.4.A` (polish + v0.1 tag) remains next in the master-plan sequence; `BU.0.B-ccf` and
  `BU.0.C-ccf` remain open in the `plan-client-contract-fixes` ad-hoc plan.

```
ec14a2e docs: update docs for plan-client-contract-fixes
137a20a docs: sync GEMINI.md with CLAUDE.md
b8dddff feat: implement plan-client-contract-fixes-task4
0fdec31 feat: implement plan-client-contract-fixes-task3
16907b1 feat: implement plan-client-contract-fixes-task2
ebae056 feat: implement plan-client-contract-fixes-task1
12911d4 docs: log BU.8.A fixture-registry-repo-e2e close-out
```

### BU.8.A closed: Fixture-registry repo read-surface e2e

- **What:** Closed out block `BU.8.A` (`8.A-fixture-registry-repo-e2e`, Phase 8 — wire-contract
  hardening). Ran via `/sdlc-task` in place on `main`; all 4 tasks passed on the first attempt:
  - task1 (`c55436e`) — `test/e2e/fixtures/workspace_fixture.dart`: fixture content constants
    (`status.md`/`handoff.md`/flow-state JSON copied verbatim from `bastion`'s parser-verified
    fixtures) plus a `provisionWorkspaceFixture()` helper that materializes a temp
    `XDG_CONFIG_HOME` `[workspaces]` registry with two fixture repos (one with
    `handoff.md`+flow-state, one without), and a hermetic gating unit test
    `workspace_fixture_test.dart`.
  - task2 (`72263eb`) — opt-in `workspaceFixture` seam on `BastionServeHarness.start()`: provisions
    the fixture env, merges `XDG_CONFIG_HOME`, exposes `fixtureRepos`, best-effort temp-dir cleanup
    in `stop()` and on the ready-timeout path; the no-fixture (Phase 7) path is unchanged.
  - task3 (`f438522`) — `test/e2e/repo_status_e2e_test.dart` (`e2e`-tagged): drives the real
    `BastionApi` repo read-surface (`GET /api/repos`, `/status`, `/workflows`, `/handoff`) against
    the fixture server, including the 404 → typed-null (C002) `handoff` branch.
  - task4 — validation-only.
  Close-out: gating suite green (`dart format` 0 changes, `flutter analyze` no issues, 292
  unit/widget tests pass via `--exclude-tags e2e`), emoji gate OK, `/code-review low` found no
  findings, `/update-docs --patch` found no STALE/MISSING (repo routes already documented in
  `docs/api-reference.md:36-38` and `docs/architecture.md:144`). Test-only change — no product/lib
  source changed.
- **Why:** Phase 8 hardens end-to-end wire-contract coverage against a real `bastion serve`. This
  block adds a hermetic fixture-workspace registry so e2e tests boot a real server against
  machine-independent fixture repos, verifying the repo read-surface (esp. the C002 → null
  `handoff` branch) at the wire level.
- **Refs:** spec `planning/8.A-fixture-registry-repo-e2e/`; master-plan Phase 8.

### BU.7.C closed: Live WS pane frame decode e2e

- **What:** Closed out block `BU.7.C` (`7.C-ws-live-frame-e2e`, Phase 7 — E2E coverage, D34 seam).
  Added `test/e2e/ws_live_frame_e2e_test.dart` — the only end-to-end exercise of
  `models/frame.dart`'s envelope decode against a real `bastion serve` frame delivered over a live
  WS pane subscription. Self-skips when no `bastion` binary or tmux is present. Gating suite green
  (`dart format` clean, `flutter analyze` clean, 287 unit/widget tests pass). Code review clean; no
  doc changes needed (test-only change).
- **Why:** Completes the Phase 7 E2E coverage seam by giving the frame decode path a live-wire test
  against a real serve frame, complementing `BU.7.B`'s session-lifecycle round-trip.
- **Refs:** spec `planning/7.C-ws-live-frame-e2e/`; master-plan Phase 7 (D34 seam).

### BU.7.B closed: Session lifecycle round-trip e2e

- **What:** Ran `/sdlc-task 7.B-session-lifecycle-e2e` in place on `main`, closing block `BU.7.B`
  (Phase 7 — E2E coverage, D34 seam). Added `test/e2e/session_lifecycle_e2e_test.dart`, an
  `@Tags(['e2e'])` test that drives the full create → list → pane → sendKeys/sendKey →
  bounded-poll pane → delete → gone round-trip against a real `bastion serve` subprocess, built on
  top of `BU.7.A`'s `withManagedSession()`/`subscribeAndCollect()` helpers. All 3 tasks passed:
  task1 + task2 (commits `28f6544`, `4d9daea`) wrote the e2e test itself. Task 3 (validate) found
  that the manual `flutter test --tags e2e` check genuinely failed (not via self-skip) with a built
  `bastion` binary + tmux present — traced to a real bug: `BastionServeHarness` spawned `bastion
  serve` with `includeParentEnvironment: false` and only `PATH` set, and without a UTF-8 locale
  some tmux builds (observed tmux 3.6b/macOS) corrupt the tab field separator in `tmux
  list-sessions -F <fmt>` output, so bastion's session parser silently drops every line and
  `GET /api/sessions` always returns `[]`. Fixed (commit `6e0273b`) by extracting a pure,
  unit-tested `bastionServeHarnessChildEnvironment()` helper in
  `test/e2e/bastion_serve_harness.dart` (forwards `PATH` always, `LANG`/`LC_ALL` when
  present+non-empty, still omits `DATABASE_URL`/engine-api-key vars) with 6 new gating unit tests
  in `bastion_serve_harness_test.dart`. This is a local workaround only — the underlying `bastion`
  (Rust) binary's locale-sensitive tmux parsing is still unfixed upstream.

  `/close-out` ran afterward (in place on `main`, no worktree to merge): gating suite green
  (`dart format` clean, `flutter analyze` clean, `flutter test --exclude-tags e2e` — 287 tests all
  passed); emoji gate clean; coverage gap scan found no blocking gaps (the new helper has 6 direct
  unit tests; the third changed file is an e2e test itself); `/code-review low` found no findings
  (all 3 changed files are under `test/e2e/`, skipped entirely by that review level's rules);
  `/update-docs --patch` found no STALE or MISSING items (e2e harness docs stay at their
  established location — `planning/harness.json`'s comment field + `CLAUDE.md` — not duplicated
  into `docs/`). Added a new `deferred`/`cross_repo` `carryover[]` entry in `planning/state.json`,
  `bastion-tmux-locale-sensitive-session-parsing`, documenting the underlying `bastion` binary
  robustness gap for a future session (in the `bastion` repo) to pick up. Wrote
  `planning/handoff.md` for the next session (next up: `BU.4.A` polish + v0.1 tag; re-verify the
  serve-api v1.0.0 pin first).
- **Why:** Phase 7's e2e coverage work — `BU.7.B` exercises the core session lifecycle round-trip
  against a real `bastion serve` process (not mocks), catching wire-contract drift the unit/widget
  test suite can't. Follows directly from `BU.7.A` (e2e support helpers) closing last session.
- **Refs:** spec at `planning/7.B-session-lifecycle-e2e/`; commits `28f6544`, `4d9daea`, `6e0273b`

## [2026-07-17]

### BU.7.A closed: E2E support helpers (managed session, frame collector, tmux guard)

- **What:** Closed `BU.7.A` via `/sdlc-task 7.A-e2e-support-helpers`, all 5 tasks passed in place
  on `main` (commits `f0ddee0`, `6eb1ff7`, `bef9586`, `0d7de15`). Added `test/e2e/e2e_support.dart`
  — a shared, non-`e2e`-tagged library exporting `tmuxAvailable()` (tmux-on-PATH self-skip guard),
  `subscribeAndCollect()` (subscribe-and-collect N decoded `BastionFrame`s from a `BastionSocket`),
  and `withManagedSession()` (create-yield-cleanup around `BastionApi.createSession`/`deleteSession`)
  — plus its own gating test suite `test/e2e/e2e_support_test.dart` (351 lines). This is shared
  test seam infrastructure for the upcoming e2e coverage blocks `BU.7.B` (session lifecycle
  round-trip e2e) and `BU.7.C` (live WS pane frame decode e2e), both of which were blocked on
  `BU.7.A` and are now unblocked/ready in the dependency graph. Also `BU.8.B` (blocked on `BU.7.A`
  + `BU.8.A`) has one of its two blockers cleared.

  Ran `/close-out` afterward (no worktree — this ran in place on `main`, so no branch merge step
  applies): `dart format` clean, `flutter analyze` clean (no issues), `flutter test --exclude-tags
  e2e` = 269 tests all green, non-gating `flutter test --tags e2e` also passed (1 test, real
  `bastion serve` subprocess). Emoji gate clean (no `.md` files changed this session). Coverage gap
  scan: no blocking gaps — both changed files are test-only (the new helper library + its own
  dedicated test file), no production source touched. `/code-review low`: both changed files are
  under `test/`, which this review level skips entirely per its own rules — zero findings.
  `/update-docs --patch`: no STALE or MISSING doc items — the new helper is internal test
  infrastructure (not user-facing), so it's NO-DOC; `docs/api-reference.md` was already current
  from the prior session's `dispose()` fix.
- **Why:** `BU.7.A` is the plan-of-record block for Phase 7 (E2E coverage, D34 seam) — providing
  the shared test-support seam that `BU.7.B`/`BU.7.C` will build their real e2e assertions on top
  of, without each duplicating session-management/frame-collection/tmux-guard boilerplate.
- **Refs:** `planning/7.A-e2e-support-helpers/tasks.md`,
  `planning/7.A-e2e-support-helpers/sdlc/sdlc-task-state.json`

### BU.ticket.e2e-serve-contract closed: service-level e2e + dispose() hang fix

- **What:** Closed `BU.ticket.e2e-serve-contract` — a service-level e2e test that boots a real,
  DB-free `bastion serve` subprocess and drives the app's real `BastionApi`/`BastionSocket`
  against it to catch wire-contract drift between BastionUI's Dart DTOs and `bastion`'s
  `serve-api.md`. Wired as a **non-gating** harness check (`flutter test --tags e2e`,
  `gates: false`), excluded from the gate via the `e2e` tag in `dart_test.yaml`; it self-skips
  when no built binary is found (see the `e2e-needs-built-bastion-binary` carryover). Running it
  surfaced and fixed a real **production hang bug**: `BastionSocket.dispose()` awaited
  `_transport.close()`, which never completes for a socket whose WS upgrade failed (fatal-auth
  401) — hanging teardown, reconnect-with-new-token, and navigation forever. The fix bounds the
  close with an injectable timeout (`_disposeCloseTimeout`, default 5s); added a unit test
  (`test/services/reconnect_test.dart`, `hangOnClose` fake) and removed the e2e
  `_disposeBounded` workaround that had masked it. Close-out: gating suite green (262 tests),
  `flutter analyze` + `dart format` clean, `/code-review low` no findings, real e2e passes
  against a built binary. Commits on `main`: 740cf77, d1599b8, f50933c (sdlc-task tasks),
  ba87374 (dispose fix), b7fad2c (docs).
- **Why:** Guards the thin-client contract (Standing Rule 6): BastionUI mirrors `bastion`'s
  serve-api schema and must catch drift before it ships. The e2e paid off immediately by
  exposing a latent teardown/reconnect hang that unit tests alone had not caught.
- **Refs:** `planning/ticket-e2e-serve-contract/tasks.md`. Next: `BU.4.A` (polish + v0.1 tag).

### BU.3.A closed: command palette (inject / spawn)

- **What:** Ran `/sdlc-flow 3.A-command-palette` on branch `3.A-command-palette-flow` against
  `planning/3.A-command-palette/tasks.md`. All 7 tasks passed: task 1 added
  `CommandMode`/`CommandModel` enums and hand-written `CommandRequest`/`CommandResponse` DTOs
  mirroring serve-api §12.1; task 2 added `BastionApi.postCommand` (`POST /api/actions/command`,
  401→`FatalAuthError`, other errors→`ApiError`, per §12.3); task 3 added a persisted,
  user-editable `commandsProvider` (add/update/delete/reorder) backed by the existing
  `secureStorageProvider`; task 4 added `CommandInvokeSheet` (inject/spawn mode toggle, session
  picker, spawn name/dir/model fields, pending + error states); task 5 added
  `QuickActionsScreen` (palette CRUD, tap-to-invoke, navigation to the server-returned session)
  plus its widget test suite; task 6 wired a third "Actions" tab into `HomeShell`'s bottom nav
  in `main.dart`; task 7 was validation-only and confirmed `dart format`/`flutter
  analyze`/`flutter test` (261 tests) all pass clean. End-of-run review returned **PASS** on the
  first attempt with no findings. Docs patched: `docs/architecture.md`, `docs/pages.md`,
  `docs/api-reference.md`. No amendments — the spec's persistence decision (reuse
  `secureStorageProvider`, no new dependency) and contract (serve-api §12 v0.4) were followed as
  written.
- **Why:** Plan-of-record block `BU.3.A` (Phase 3 — Quick-action launcher), unblocked
  2026-07-16 once `bastion` block `BA.11.E` shipped `POST /api/actions/command` (serve-api v0.5).
  Delivers the app's only write-path action beyond session control: firing a slash-command into
  an existing session or spawning a new one, then auto-opening its pane.
- **Refs:** `planning/3.A-command-palette/tasks.md`

### BU.3.A Close-Out — Command Palette Flow
- **What:** Ran /close-out --merge-branch after /sdlc-flow 3.A-command-palette completed (all 7 tasks passed, end-of-run review PASS, 261 tests green, PR #1 opened at https://github.com/bredmond1019/bastion-ui/pull/1). Close-out re-verified the gating suite (dart format, flutter analyze, flutter test — all clean), ran a coverage gap scan (no blocking gaps — every changed source file has a matching test file), ran /code-review low on the diff (no findings), and ran /update-docs --patch (confirmed docs/architecture.md, docs/pages.md, docs/api-reference.md were already patched by the sdlc-flow's own docs stage — nothing further needed). Wrote planning/handoff.md documenting the state. The remaining step is close-out's Step 5b: fast-forward-merge 3.A-command-palette-flow into main and run mev emit-state --write.
- **Why:** BU.3.A (command palette / inject-spawn quick-actions) is the plan-of-record block; this closes it out cleanly per the standing SDLC workflow before starting BU.4.A (polish + v0.1 tag).
- **Refs:** PR #1 (https://github.com/bredmond1019/bastion-ui/pull/1), planning/3.A-command-palette/tasks.md, planning/3.A-command-palette/sdlc/sdlc-flow-state.json, planning/handoff.md

---

## [2026-07-07]

### BU.ticket.ws-debounce closed: WebSocket state-stream debounce

- **What:** Ran `/sdlc-task ticket-ws-debounce` in place on `main` (no worktree) against
  `planning/ticket-ws-debounce/tasks.md`. All 5 tasks passed: added `rxdart: ^0.28.0` to
  `pubspec.yaml` (`822be72`); applied `.debounceTime(~150ms)` (trailing) to
  `workflows_provider.dart`, `pane_provider.dart`, and `sessions_provider.dart`, each filtering to
  its own repo/session/topic before debouncing, while leaving `connection_provider.dart`
  undebounced with an explanatory comment (`705fa60`); documented (comment-only) that
  `needsInputEventsProvider` (`events_provider.dart`) is deliberately never debounced (`14d01a6`);
  added `test/state/ws_debounce_test.dart` using `fake_async` asserting burst coalescing, spaced
  events each emitting, and `needsInput` events never dropped (`cd0f5ec`); final validation task
  green with no code changes. Then ran `/close-out`: `dart format`, `flutter analyze`, `flutter
  test` (225 tests, all green), emoji gate all pass; coverage scan found no blocking gaps;
  `/code-review low` on the diff since `1370ca0` found no issues; patched
  `docs/architecture.md`'s "REST + WS seed/live pattern" section documenting the new debounce
  behavior and the `needsInputEventsProvider` exclusion. `planning/state.json`'s
  `BU.ticket.ws-debounce` block flipped `open` → `closed`.
- **Why:** Standalone performance ticket (queued in the Tickets track) to stop WebSocket
  state-refresh streams thrashing Riverpod rebuilds under rapid pane switching / event floods,
  while carefully never debouncing discrete `needsInput` approval prompts. Picked up because the
  plan-of-record block `BU.3.A` (command palette) remains blocked on `bastion` shipping serve-api
  v0.4 (`BA.11.E` not yet built, verified 2026-07-02), so this ticket was available unblocked
  work.
- **Refs:** `planning/ticket-ws-debounce/tasks.md`

---

## [2026-07-02]

### BU.2.A closed out: clean review, verified docs, fresh handoff to BU.3.A

- **What:** Closed out BU.2.A handoff. This session merged the BU.2.A
  (`2.A-dashboard-repo-detail`) sdlc-flow work (already logged in an earlier entry today) into
  `main` via `/clean-worktree`, then ran a light `/code-review low` on the merged `lib/` diff (no
  findings), verified `docs/index.md`, `docs/architecture.md`, `docs/api-reference.md`,
  `docs/pages.md` were accurate and complete, then ran `/handoff`: updated `planning/state.json`
  (BU.2.A block status open→closed, all 8 tasks status→`"done"` — authored edit), ran `mev
  emit-state --write` to regenerate the derived `focus` view (BU.3.A is now the sole
  `focus.next` entry, BU.4.A's `blocked_by` correctly shows only BU.3.A), confirmed `mev
  validate-brain --state` shows 0 errors / no new warnings, and wrote a fresh
  `planning/handoff.md` replacing the stale BU.1.A-era one, now pointing the next agent at
  BU.3.A (command palette, consumes serve-api v0.4).
- **Why:** Standard end-of-block close-out procedure — merge, review, verify docs, then hand off
  cleanly with `state.json` kept in sync so the next agent's `/prime` surfaces accurate focus.
- **Refs:** `planning/2.A-dashboard-repo-detail/`; `planning/state.json`; `planning/handoff.md`.

---

## [run: 2026-07-02]

Ran the `2.A-dashboard-repo-detail` sdlc-flow across 8 tasks, all passed, review verdict **PASS**. Task 1 added `RepoSummaryDto`/`RepoStatusDto`/`HandoffInfo`/`WorkflowStateDto` (de)serialization mirroring serve-api v0.3 §11 (verifying against the spec directly caught that `current_task` is a JSON int, not the string the task spec's prose table implied). Task 2 added `getRepos()`/`getRepoStatus()`/`getRepoHandoff()`/`getRepoWorkflows()` to `BastionApi`, with `getRepoHandoff()` surfacing a 404/`C002` (no `handoff.md`) as a typed null. Task 3 added `repos_provider.dart` (REST-seeded repo list, pull-to-refresh) and `workflows_provider.dart` (per-repo status+workflows, auto-refetching on `workflow_done` events). Task 4 built the dashboard screen listing every workspace-registry repo with a per-repo `StatusBadge` (idle/in-flight/handoff-pending). Task 5 built the repo-detail screen (parsed status/momentum, handoff markdown via a local `repoHandoffProvider`, per-workflow progress rows). Task 6 added a second notification channel (`notifyWorkflowDone`) bridging `workflow_done` events to local notifications. Task 7 — learning directly from `BU.1.A`'s review FAIL — made wiring its own explicit task: `HomeShell` now has a bottom-nav tab bar (Sessions/Dashboard), routes `/repos/{name}` to `RepoDetailScreen`, activates the new notification wiring, and shows a foreground `SnackBar` on `workflow_done`. Task 8 confirmed all validation commands green with no code changes needed. The consolidated end-of-run review passed on the first attempt — no dead-code wiring gap this time. Two contract-driven deviations from the master-plan skeleton (no `frame.dart` change needed; PR-link acceptance criterion dropped, no field exists in v0.3) were already documented in the spec's own Context Pointers/Notes and are now folded into its Amendment Log. Docs (`docs/index.md`, `docs/architecture.md`, `docs/api-reference.md`, `docs/pages.md`) were created/updated to cover the new dashboard/repo-detail surface. Final state: 222 tests green, `dart format`/`flutter analyze` clean. Next: `BU.3.A` — command palette (inject/spawn), consumes serve-api v0.4 (`bastion` Block I).

```
09f9c2a chore: flow state — docs
a1ee5a6 docs: update docs for 2.A-dashboard-repo-detail
f78c7c5 chore: flow state — task 8 passed
34830d4 chore: flow state — task 7 passed
56247df feat: implement 2.A-dashboard-repo-detail-task7
64d4116 chore: flow state — task 6 passed
55c2226 feat: implement 2.A-dashboard-repo-detail-task6
5d64c83 chore: flow state — task 5 passed
```

---

## [2026-07-02]

### BU.1.A closed: post-review wiring fix + provider-scope visibility bug found by coverage gap-scan

- **What:** Closed out spec `1.A-sessions-list-live-pane-approvals` (`BU.1.A`). The prior `sdlc-flow`
  run built all 8 tasks correctly in isolation, but its own consolidated review caught that
  `main.dart` never routed to the new `SessionsListScreen`/`SessionDetailScreen`/
  `notificationWiringProvider` — dead code, unreachable from the running app. Fixed by wiring
  `HomeShell` to render the sessions list once connected (commit `6787207`), merged to `main` via
  `/clean-worktree`. Ran `/code-review low` on the merged diff — no findings (that bug class isn't
  visible from a diff alone). Then ran `/close-out`: its coverage gap-scan wrote a widget test
  proving the first fix, and that test caught a second, more serious bug — the app's `Navigator`
  lives inside `MaterialApp`, an ancestor of `HomeShell`, so a `ProviderScope` override nested
  inside `HomeShell`'s body (the first fix's approach) is invisible to routes the `Navigator`
  pushes. Tapping a session card in the real app would have thrown `UnimplementedError` on
  `SessionDetailScreen`. Fixed by changing `bastionSocketProvider`/`bastionApiProvider` from
  throw-until-overridden `Provider<T>` to mutable `StateProvider<T?>` set once on the single root
  `ProviderScope` (commit `bc9d480`) — visible everywhere, including pushed routes. Downstream
  providers now throw `StateError` if read before connect, preserving the fail-loudly intent. Also
  patched `README.md`'s empty template placeholder sections (Prerequisites/Setup/Running
  locally/Tests) and linked `planning/decisions/index.md` (commit `e8c7253`). Final state: 162
  tests green, `dart format`/`flutter analyze` clean, all merged to `main` (no remote configured
  for this repo, so nothing was pushed).
- **Why:** Close out `BU.1.A` cleanly and surface a real correctness bug (provider-scope
  visibility across `Navigator`-pushed routes) before it shipped, so `BU.2.A`/`BU.3.A` inherit the
  fix rather than repeating the mistake.
- **Refs:** `planning/1.A-sessions-list-live-pane-approvals/`; commits `6787207`, `bc9d480`,
  `e8c7253`.

---

## [run: 2026-07-02]

Ran the `1.A-sessions-list-live-pane-approvals` sdlc-flow across 8 tasks, all of which passed individually. Task 1 added `SessionDto`/`PaneDto` models plus typed v0.2 WS-hub frame kinds (`SessionsFrame`, `PaneFrame`, `EventFrame`) and client→server encoders (subscribe/unsubscribe/send/send_key). Task 2 built out the v0.1 session REST surface on `BastionApi` (getSessions, getPane, sendKeys, sendKey, createSession, deleteSession), extending `HttpTransport` with POST/DELETE. Task 3 added `sessions_provider.dart` (REST-seeded, WS-kept-live sessions list) and `events_provider.dart` (needs-input event stream + per-session flag set), injected via placeholder providers since `main.dart` was reserved for Task 7. Task 4 added a per-session `pane_provider.dart` family that REST-seeds and WS-subscribes a live pane buffer with seq-ordered updates and autoDispose unsubscribe. Task 5 built the sessions-list screen with live session cards (running/idle badge, needs-input flag) and tap navigation toward a session-detail route. Task 6 built the session-detail screen (auto-scrolling live pane, free-text send bar, quick-approve button row mapped to sendKeys/sendKey). Task 7 added a `NotificationService` wrapping `flutter_local_notifications` and a `notificationWiringProvider` bridging needs-input events to local notifications, initialized in `main.dart` — but deliberately not wired into `HomeShell.build()` because the sessions/pane/events providers weren't yet mounted into the app shell. Task 8 was a clean validation-only pass (format/analyze/test all green). The end-of-run review returned a **FAIL** verdict and the flow bailed: entire spec's deliverables (sessions list, session detail, notification bridge) are unreachable from the running app — `main.dart`/`HomeShell` was never updated to route to them, so the app's actual behavior is unchanged from before the spec despite all new code existing and passing isolated tests. Each task individually deferred the `main.dart`/`HomeShell` wiring to a later task's scope, and no task ever closed that loop, leaving four fully-tested but dead-code deliverables. Next: a follow-up task/spec to wire `SessionsListScreen`, `SessionDetailScreen`, and `notificationWiringProvider` into `main.dart`/`HomeShell` so the app actually routes to and activates them, then re-run review.

```
5598703 chore: flow state — review FAIL — bail
1564472 chore: flow state — task 8 passed
e4ed443 chore: flow state — task 7 passed
3a5ea8a feat: implement 1.A-sessions-list-live-pane-approvals-task7
b797e4b chore: flow state — task 6 passed
d9b41b8 feat: implement 1.A-sessions-list-live-pane-approvals-task6
2fb852c chore: flow state — task 5 passed
ae94f7c feat: implement 1.A-sessions-list-live-pane-approvals-task5
```

---

## 2026-06-27

Completed spec `0.A-app-foundation` (Phase 0, Block A) across 7 tasks — all passed, review verdict PASS. Task 1 scaffolded the Flutter Android app (`com.bastionui/bastion_ui`) with riverpod, web_socket_channel, flutter_secure_storage, flutter_markdown, and flutter_local_notifications, replacing the generated `main.dart` with a `ProviderScope` root. Task 2 built the pure-Dart contract-mirroring model layer: a sealed `BastionFrame` hierarchy (`echo`, `error`, `unknown`, `malformed`) and v0 DTOs (`HealthDto`, `ErrorPayload`), with 22 round-trip unit tests. Task 3 added the secure connection provider (host/port/token all in `flutter_secure_storage`) and a settings screen with field validation. Task 4 implemented `BastionSocket` — a `WsTransport`-abstracted WebSocket service with a typed frame stream, sync status stream, capped exponential-backoff reconnect, and fatal auth detection, proven by 14 unit tests against a fake transport. Task 5 delivered `BastionApi` — a REST client with bearer auth, `GET /health → HealthDto`, typed `FatalAuthError` on 401, and 11 unit tests. Task 6 wired up the `ConnectionBanner` widget (live status strip), integrated `HomeShell` into `main.dart` for socket lifecycle management and settings routing, bringing total test count to 69 green. Task 7 was validation-only: `dart format`, `flutter analyze`, and `flutter test` all clean. Next: Phase 1 Block A (session control screens + approve buttons) — blocked until `bastion` ships serve-api v0.1 (Block D) and v0.2 (Block E).

```
1395673 chore: flow state — docs
0d13789 docs: update docs for 0.A-app-foundation
632c2d3 chore: flow state — task 7 passed
cfe749b chore: flow state — task 6 passed
d84c5ce feat: implement 0.A-app-foundation-task6
6ff58af chore: flow state — task 5 passed
d876577 feat: implement 0.A-app-foundation-task5
66c6162 chore: flow state — task 4 passed
```

---

## 2026-06-26

Phase 0 Block A (0.A-app-foundation) complete: all 7 tasks passed, review clean (no findings), branch 0.A-app-foundation-flow-2 ready to merge into main. Flutter app foundation shipped with 69 green tests covering scaffolding, pure-Dart contract mirroring, secure storage, reconnecting WebSocket socket service with capped exponential backoff, REST client, and connection-status banner.

```diff
 .gitignore                                         |  45 ++
 .metadata                                          |  30 +
 analysis_options.yaml                              |  28 +
 android/.gitignore                                 |  14 +
 android/app/build.gradle.kts                       |  45 ++
 android/app/src/debug/AndroidManifest.xml          |   7 +
 android/app/src/main/AndroidManifest.xml           |  45 ++
 .../com/bastionui/bastion_ui/MainActivity.kt       |   5 +
 .../main/res/drawable-v21/launch_background.xml    |  12 +
 .../src/main/res/drawable/launch_background.xml    |  12 +
 .../app/src/main/res/mipmap-hdpi/ic_launcher.png   | Bin 0 -> 544 bytes
 .../app/src/main/res/mipmap-mdpi/ic_launcher.png   | Bin 0 -> 442 bytes
 .../app/src/main/res/mipmap-xhdpi/ic_launcher.png  | Bin 0 -> 721 bytes
 .../app/src/main/res/mipmap-xxhdpi/ic_launcher.png | Bin 0 -> 1031 bytes
 .../src/main/res/mipmap-xxxhdpi/ic_launcher.png    | Bin 0 -> 1443 bytes
 android/app/src/main/res/values-night/styles.xml   |  18 +
 android/app/src/main/res/values/styles.xml         |  18 +
 android/app/src/profile/AndroidManifest.xml        |   7 +
 android/build.gradle.kts                           |  24 +
 android/gradle.properties                          |   6 +
 android/gradle/wrapper/gradle-wrapper.properties   |   5 +
 android/settings.gradle.kts                        |  26 +
 lib/main.dart                                      | 153 ++++++
 lib/models/dto.dart                                |  69 +++
 lib/models/frame.dart                              | 145 +++++
 lib/screens/settings_screen.dart                   | 192 +++++++
 lib/services/bastion_api.dart                      | 191 +++++++
 lib/services/bastion_socket.dart                   | 333 +++++++++++
 lib/state/connection_provider.dart                 | 174 ++++++
 lib/widgets/connection_banner.dart                 |  96 ++++
 log.md                                             |  17 +
 .../0.A-app-foundation/sdlc/sdlc-flow-state.json   | 391 +++++++++++++
 planning/0.A-app-foundation/sdlc/worklog.md        |  42 ++
 planning/0.A-app-foundation/tasks.md               |   4 +-
 planning/status.md                                 |   8 +-
 pubspec.lock                                       | 610 +++++++++++++++++++++
 pubspec.yaml                                       |  96 ++++
 test/models/frame_test.dart                        | 234 ++++++++
 test/services/api_test.dart                        | 193 +++++++
 test/services/reconnect_test.dart                  | 414 ++++++++++++++
 test/state/connection_provider_test.dart           | 244 +++++++++
 test/widget_test.dart                              | 101 ++++
 test/widgets/connection_banner_test.dart           | 124 +++++
 43 files changed, 4172 insertions(+), 6 deletions(-)
```

---

## 2026-06-26

Project initialized from `base-template` (commit `5afd222c8f43af0094800f3bebc64fbdfb4bd167`) via `/new-project`.
Planning infrastructure scaffolded: `planning/context.md`, `planning/status.md`,
`planning/master-plan.md`, `planning/index.md`, `planning/harness.json`, `planning/decisions/`,
and the root `CLAUDE.md` / `README.md`. Concept folders (`planning/<concept>/`) are created on
demand by the SDLC pipeline. Curated SDLC harness (`.claude/`) in place.

Next step: run `/generate-tasks` for the first Phase 0 block to begin the pipeline.

```diff
(no code changes — planning files only)
```
