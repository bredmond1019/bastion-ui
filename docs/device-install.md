---
type: Guideline
title: Device Install — Pixel Tablet & Pixel Phone
description: How to wirelessly install BastionUI on a Pixel tablet or phone and point it at bastion serve over Tailscale.
doc_id: device-install
layer: [surface]
project: bastion-ui
status: active
keywords: [install, pixel, tablet, adb, wireless debugging, tailscale, deployment]
related: [capabilities, architecture, api-reference]
---

# Device Install — Pixel Tablet & Pixel Phone

How to get BastionUI running on a real Android device (Pixel Tablet or Pixel phone) and
connected to `bastion serve` over Tailscale, with no cable required after the initial
pairing.

## What this page is for

You have the app building on an emulator and now want it on the actual tablet you will
use it from. Four steps: unlock wireless debugging, pair once over the LAN, install, then
point the app at your server. After that, every later install works over Tailscale with
no cable and no re-pairing.

Once it is installed, what you can do with it: [`capabilities.md`](capabilities.md).

## Quickstart (device already paired)

```bash
adb connect <device-tailscale-ip>:<debug-port>
flutter run -d <device-id>
```

If `adb connect` fails or `flutter devices` is empty, you have not paired yet — start at
step 1.

## 1. One-time device setup

On the device (tablet or phone):

1. Settings → About → tap **Build number** 7x to unlock Developer options.
2. Settings → System → Developer options → enable **Wireless debugging**.
3. Confirm Tailscale is installed and **actively connected** on the device (check the
   Tailscale app itself, not just `tailscale status` on another node — enrollment alone
   doesn't mean the client is up).

On this Mac, if `adb` isn't installed:

```bash
brew install --cask android-platform-tools
```

## 2. Pair once (must be on the same LAN as this Mac — Tailscale IP does not work for pairing)

1. On the device: Developer options → Wireless debugging → **Pair device with pairing code**.
   This shows a pairing IP:port and a 6-digit code.
2. On the Mac:
   ```bash
   adb pair <device-pairing-ip>:<pairing-port>
   # enter the 6-digit code when prompted
   adb connect <device-ip>:<debug-port>   # port shown on the main Wireless debugging screen
   ```
3. `flutter devices` should now list the device.

Once paired, `adb connect` also works over the device's **Tailscale IP** for future sessions
(pairing itself requires the LAN; reconnecting afterward does not).

## 3. Build and install

```bash
flutter run -d <device-id>              # debug build, installs + launches
# or
flutter build apk --release
flutter install -d <device-id>          # installs the release APK
```

## 4. Point the app at the Mac Mini

`bastion serve` on the Mac Mini is reachable over Tailscale. Confirm it's up first:

```bash
cd /Users/brandon/Dev/agentic-portfolio
./scripts/health_check.sh
```

In the app's **Settings** screen, enter:

| Field | Value |
|---|---|
| Host | the Mac Mini's Tailscale IP — run `tailscale ip -4` on the Mac Mini, or read it from the Tailscale admin console; do not hardcode it anywhere shared (a `100.x.y.z` address is a real address on your tailnet, not a placeholder) |
| Port | the live bound port — not the `4317` doc default in `serve-api.md`; confirm against `./scripts/health_check.sh`'s `bastion serve (http://...)` line |
| Token | the Mac Mini's `BASTION_SERVE_TOKEN` value |

The bearer token is stored via `flutter_secure_storage` on-device (Standing Rule 7 — never
`shared_preferences`).

## Repeat for a second device

Steps 1–3 are per-device (each device pairs and installs independently); step 4's host/port/
token are the same for every device since they all point at the same `bastion serve` instance.
