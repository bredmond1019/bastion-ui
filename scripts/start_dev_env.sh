#!/usr/bin/env bash
# Boots a local dev environment for manual, real-backend testing: an Android
# emulator + a `bastion serve` instance on the same host, then (by default)
# launches `flutter run` against it.
#
# Unlike scripts/run_patrol_smoke.sh (self-skips on a missing prerequisite,
# non-gating CI-style check), this is an interactive convenience script: it
# bails loudly with a specific diagnosis on any failure, and leaves the
# server running on success so the emulator can be reused across `flutter
# run` invocations without a restart.
#
# Usage: scripts/start_dev_env.sh [--no-run] [--avd NAME] [--port PORT] [--token TOKEN]
#
#   --no-run       Start the emulator + server, print connection info, then
#                   exit instead of launching `flutter run`.
#   --avd NAME      Android Virtual Device to boot if none is attached.
#                   Default: Pixel_9 (or $AVD_NAME).
#   --port PORT     Port for `bastion serve`. Default: 4317 (or $PORT).
#   --token TOKEN   Bearer token for `bastion serve`. Default: patrol-smoke-token
#                   (or $TOKEN).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RUN_FLUTTER=1
AVD_NAME="${AVD_NAME:-Pixel_9}"
PORT="${PORT:-4317}"
TOKEN="${TOKEN:-patrol-smoke-token}"
STARTED_SERVER=0
SERVER_PID=""
SERVER_LOG="/tmp/bastion-serve-dev.log"

while [ $# -gt 0 ]; do
  case "$1" in
    --no-run) RUN_FLUTTER=0; shift ;;
    --avd) AVD_NAME="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --token) TOKEN="$2"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

info() { echo "INFO:  $1"; }
ok()   { echo "OK:    $1"; }
fail() {
  echo "ERROR: $1" >&2
  [ -n "${2:-}" ] && echo "       $2" >&2
  exit 1
}

# Only tear down what THIS run started, and only on a failure path — a
# clean exit leaves the emulator/server up for the caller to use.
cleanup_on_failure() {
  status=$?
  if [ "$status" -ne 0 ] && [ "$STARTED_SERVER" = "1" ] && [ -n "$SERVER_PID" ]; then
    info "cleaning up: killing bastion serve (pid $SERVER_PID) started by this run"
    kill "$SERVER_PID" 2>/dev/null
  fi
}
trap cleanup_on_failure EXIT

# ---- Android SDK env ----
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
[ -d "$ANDROID_HOME" ] || fail "Android SDK not found at \$ANDROID_HOME ($ANDROID_HOME)" \
  "set ANDROID_HOME, or install the SDK via Android Studio."
if [ -z "${JAVA_HOME:-}" ]; then
  JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  [ -d "$JBR" ] && export JAVA_HOME="$JBR"
fi
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$HOME/.pub-cache/bin${JAVA_HOME:+:$JAVA_HOME/bin}"

command -v adb >/dev/null 2>&1 || fail "adb not found on PATH after setting ANDROID_HOME" \
  "expected it under \$ANDROID_HOME/platform-tools ($ANDROID_HOME/platform-tools)."

# ---- Emulator: reuse an attached device, or boot one ----
DEVICE="$(adb devices | awk '$2 == "device" {print $1; exit}')"
if [ -n "$DEVICE" ]; then
  ok "reusing already-attached device: $DEVICE"
else
  command -v emulator >/dev/null 2>&1 || fail "emulator command not found" \
    "expected it under \$ANDROID_HOME/emulator ($ANDROID_HOME/emulator)."
  AVAILABLE_AVDS="$(emulator -list-avds 2>/dev/null)"
  echo "$AVAILABLE_AVDS" | grep -qx "$AVD_NAME" || fail "AVD '$AVD_NAME' not found" \
    "available AVDs: $(echo "$AVAILABLE_AVDS" | tr '\n' ' ')
       create one in Android Studio's Device Manager, or pass --avd <name>."

  info "booting AVD '$AVD_NAME' (this can take 30-60s)..."
  nohup emulator -avd "$AVD_NAME" >/tmp/bastion-ui-emulator.log 2>&1 &

  info "waiting for a device to attach..."
  BOOTED=0
  for _ in $(seq 1 60); do
    DEVICE="$(adb devices | awk '$2 == "device" {print $1; exit}')"
    [ -n "$DEVICE" ] && { BOOTED=1; break; }
    sleep 1
  done
  [ "$BOOTED" = "1" ] || fail "no device attached after 60s" \
    "see /tmp/bastion-ui-emulator.log. Try launching Android Studio's AVD Manager directly."

  info "device attached ($DEVICE), waiting for boot to complete..."
  BOOT_DONE=0
  for _ in $(seq 1 60); do
    [ "$(adb -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && { BOOT_DONE=1; break; }
    sleep 1
  done
  [ "$BOOT_DONE" = "1" ] || fail "emulator attached but never finished booting (waited 60s)" \
    "see /tmp/bastion-ui-emulator.log, or wipe the AVD's data in Android Studio if this persists."
  ok "emulator '$AVD_NAME' booted: $DEVICE"
fi

# ---- bastion binary (same search order as run_patrol_smoke.sh / bastion_serve_harness.dart) ----
BASTION_BIN="${BASTION_BIN:-}"
if [ -z "$BASTION_BIN" ]; then
  for candidate in ../bastion/target/release/bastion ../bastion/target/debug/bastion; do
    [ -x "$candidate" ] && BASTION_BIN="$candidate" && break
  done
fi
[ -z "$BASTION_BIN" ] && BASTION_BIN="$(command -v bastion || true)"
[ -n "$BASTION_BIN" ] || fail "no bastion binary found" \
  "build one: cd ../bastion && cargo build --release. Or set BASTION_BIN=/path/to/bastion."

# ---- bastion serve: reuse if already answering, else start it ----
if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  ok "reusing already-running bastion serve on :$PORT"
else
  PORT_HOLDER="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1)"
  if [ -n "$PORT_HOLDER" ]; then
    HOLDER_CMD="$(ps -p "$PORT_HOLDER" -o comm= 2>/dev/null)"
    fail "port $PORT is already in use by something that isn't answering /health" \
      "pid $PORT_HOLDER ($HOLDER_CMD). Kill it, or pass --port <other port>."
  fi

  ENV_FILE="../bastion/.env"
  if [ -f "$ENV_FILE" ]; then
    info "sourcing $ENV_FILE for DATABASE_URL / BASTION_ENGINE_API_KEY"
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  else
    info "no $ENV_FILE found — starting without it (engine routes will not mount)"
  fi

  info "starting bastion serve on :$PORT..."
  "$BASTION_BIN" serve --addr "0.0.0.0:$PORT" --token "$TOKEN" >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
  STARTED_SERVER=1

  READY=0
  for _ in $(seq 1 20); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      fail "bastion serve exited immediately (pid $SERVER_PID died)" \
        "last output from $SERVER_LOG:
$(tail -n 20 "$SERVER_LOG")"
    fi
    curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { READY=1; break; }
    sleep 0.5
  done
  [ "$READY" = "1" ] || fail "bastion serve did not answer /health on :$PORT within 10s" \
    "last output from $SERVER_LOG:
$(tail -n 20 "$SERVER_LOG")"
  ok "bastion serve is up on :$PORT (pid $SERVER_PID, log: $SERVER_LOG)"

  if grep -q "engine routes mounted" "$SERVER_LOG"; then
    ok "engine routes mounted (DATABASE_URL + BASTION_ENGINE_API_KEY present)"
  else
    info "engine routes NOT mounted — Phase 12 (BU.12.x) engine calls will 404. See $SERVER_LOG."
  fi
fi

echo
ok "dev environment ready: device $DEVICE, bastion serve on 127.0.0.1:$PORT (token: $TOKEN)"

if [ "$RUN_FLUTTER" = "1" ]; then
  echo
  info "launching: flutter run -d $DEVICE"
  trap - EXIT # a `flutter run` failure shouldn't tear down the server underneath a live session
  exec flutter run -d "$DEVICE"
else
  echo "Next: point Settings at 127.0.0.1:$PORT (or 10.0.2.2:$PORT from the emulator) with token '$TOKEN',"
  echo "then run: flutter run -d $DEVICE"
fi
