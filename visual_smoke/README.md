# Visual smoke runs

Deliberate, human-triggered visual captures of BastionUI screens driven against
a real `bastion serve` — not part of the gating suite (`planning/harness.json`),
not run by `/sdlc-task`/`/sdlc-flow`, not run on every test pass. Run this only
when you actually want a fresh visual record: after a UI-affecting change, or
periodically to catch drift.

## Why this exists, and why it's not automatic

Screenshotting every test run would silently pile up hundreds of near-duplicate
PNGs with no signal. This directory is for **intentional** baseline/comparison
captures instead — few, well-labeled, kept around specifically so a later run
can be diffed against a known-good prior state.

## Layout

```
visual_smoke/
  README.md              tracked in git — this file
  runs/                  gitignored — screenshots live on disk only, never committed
    <YYYY-MM-DD_HHMMSS>/
      manifest.md         environment + screen list for this run
      01_*.png .. NN_*.png
    latest -> runs/<most-recent-timestamp>   (convenience symlink, gitignored)
```

Each run is its own timestamped folder — never overwritten, so you can always
look back at exactly what a given run captured. `manifest.md` records the
environment (device, app build, backend commit, data fixtures) so a screenshot
diff is meaningful — a UI change and a fixture-data change look very different
in the images, and the manifest is how you tell them apart.

## Capturing a new run

1. Boot the target device/emulator and a real `bastion serve` (see
   `patrol_test/smoke_test.dart`'s header for the harness pattern — same real
   backend, no mocks).
2. Install the debug APK (`flutter build apk --debug && adb install -r
   build/app/outputs/flutter-apk/app-debug.apk`).
3. Drive the same screen sequence as the existing runs (see any prior
   `manifest.md`'s Screens table for the canonical list) via `adb shell input
   tap/text` — read exact tap coordinates from `adb shell uiautomator dump`
   bounds, not from eyeballing a downscaled screenshot preview.
4. Capture each screen with `adb exec-out screencap -p > <name>.png`.
5. Create `runs/<YYYY-MM-DD_HHMMSS>/`, write a `manifest.md` (copy the
   structure from the most recent run), and update the `latest` symlink:
   `ln -sfn runs/<new-timestamp> visual_smoke/latest`.

## Comparing runs

There's no automated diff tool wired up yet — compare manually (`open
visual_smoke/runs/<a>/07_dashboard.png visual_smoke/runs/<b>/07_dashboard.png`,
or view both via Read). If this becomes a recurring practice, revisit adding
a pixel-diff step (e.g. `magick compare`) rather than eyeballing every time.

## Functional coverage vs. visual coverage

`patrol_test/smoke_test.dart` is the functional counterpart — it asserts the
same screens actually render live backend data (real sessions, real repos)
and is meant to be re-run freely. This directory is for the visual record,
not the assertions.
