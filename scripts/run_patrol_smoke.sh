#!/usr/bin/env bash
# Manual, non-gating Patrol smoke check — mirrors `e2e-serve-contract`'s
# self-skip contract, and Next.js's `uiTest` live-smoke-check role (that
# stage is playwright-cli/web-specific engine mechanism; a mobile app needs
# its own driver, hence this script instead of `uiTest.enabled`).
#
# NEVER runs automatically: planning/harness.json registers this as
# `gates: false`, and the SDLC engines only auto-run `gates:true` checks per
# task (testDepth=fast, the project default) — this command only executes
# when a human or agent runs it deliberately.
#
# Self-skips (exit 0) when the environment can't support it: no attached
# Android device/emulator, or no built `bastion` binary. Otherwise starts a
# `bastion serve` on 127.0.0.1:4317 (reusing one already running there) and
# runs patrol_test/smoke_test.dart against it.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PORT=4317
TOKEN="patrol-smoke-token"
STARTED_SERVER=0
SERVER_PID=""

skip() {
  echo "SKIPPED: $1"
  exit 0
}

cleanup() {
  if [ "$STARTED_SERVER" = "1" ] && [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
  fi
}
trap cleanup EXIT

# ---- Android SDK env (same defaults as the manual run) ----
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
if [ -z "${JAVA_HOME:-}" ]; then
  JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  [ -d "$JBR" ] && export JAVA_HOME="$JBR"
fi
export PATH="$PATH:$ANDROID_HOME/platform-tools:$HOME/.pub-cache/bin${JAVA_HOME:+:$JAVA_HOME/bin}"

# ---- Device check ----
command -v adb >/dev/null 2>&1 || skip "adb not found (ANDROID_HOME unset or SDK missing)"
DEVICE="$(adb devices | awk '$2 == "device" {print $1; exit}')"
[ -n "$DEVICE" ] || skip "no attached Android device/emulator (adb devices is empty)"

# ---- bastion binary check (same search order as test/e2e/bastion_serve_harness.dart) ----
BASTION_BIN="${BASTION_BIN:-}"
if [ -z "$BASTION_BIN" ]; then
  for candidate in ../bastion/target/release/bastion ../bastion/target/debug/bastion; do
    [ -x "$candidate" ] && BASTION_BIN="$candidate" && break
  done
fi
[ -z "$BASTION_BIN" ] && BASTION_BIN="$(command -v bastion || true)"
[ -n "$BASTION_BIN" ] || skip "no bastion binary found (build it in ../bastion, or set BASTION_BIN)"

# ---- Start bastion serve if nothing is already answering on $PORT ----
if ! curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  "$BASTION_BIN" serve --addr "0.0.0.0:$PORT" --token "$TOKEN" >/tmp/patrol-smoke-bastion-serve.log 2>&1 &
  SERVER_PID=$!
  STARTED_SERVER=1
  for _ in $(seq 1 20); do
    curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
    sleep 0.5
  done
  curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 || skip "bastion serve did not become ready on :$PORT — see /tmp/patrol-smoke-bastion-serve.log"
fi

echo "Running Patrol smoke test on $DEVICE against bastion serve on :$PORT..."
patrol test -t patrol_test/smoke_test.dart -d "$DEVICE"
