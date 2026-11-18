# quant-terminal-ios

SwiftUI companion app (iOS 17+) for [quant-terminal-web](https://github.com/juanmmm21/quant-terminal-web):
the status of the paper-trading bots, their P&L, push alerts (APNs) and the **emergency stop**.
Paper trading runs on the Binance **testnet**: test funds, never real money.

| Tab | What it shows |
|-----|---------------|
| **Resumen** | engine state, paper-trader heartbeat and venue, promoted strategy (flagged if it did not pass the out-of-sample gate), equity, P&L, return, position, equity chart, emergency stop |
| **Alertas** | the server's alerts (emergency stop applied or pending, orders in unknown state, risk rejections, halts, fills) |
| **Ajustes** | server URL, device token (Keychain), enable push alerts |

The emergency stop asks for confirmation, then calls `POST /api/v1/bot/panic`. The server only
records the stop, so it works even when the exchange is unreachable; the paper trader then
cancels open orders and retries every cycle until it can. Resuming requires the operator token,
not a device token.

## Layout

```text
QuantKit/                     Swift package: models + network layer (Foundation only)
  Sources/QuantKit/           QuantAPIClient, Overview models, ISO-8601 parsing for Python dates
  Tests/QuantKitTests/        XCTest; fixtures are real responses from the quant-terminal-web API
App/QuantTerminal/            SwiftUI app (Observation, Swift Charts, Keychain, UserNotifications)
QuantTerminal.xcodeproj       app target + local package; shared scheme "QuantTerminal"
scripts/generate_xcodeproj.py rebuilds the .xcodeproj reproducibly (not needed when using Xcode)
.github/workflows/ios.yml     QuantKit tests on Linux and macOS, app build + tests on the iOS Simulator
```

`QuantKit` keeps money as `Decimal` parsed from the API's decimal strings (never `Double`), maps
HTTP errors to typed errors (401 revoked token, 403 wrong scope, 503 control disabled…), refuses
plain-HTTP servers except loopback and private VPN addresses (Tailscale `100.x`), and never sends a
request without a token. Its transport is injectable, which is how the tests run without a network.

## Run the tests

```bash
cd QuantKit && swift test                      # macOS or Linux, no simulator needed
xcodebuild -scheme QuantKit -destination 'platform=iOS Simulator,name=iPhone 15' test   # from QuantKit/
```

## Build, sign and install (what you need to do)

1. Open `QuantTerminal.xcodeproj` in Xcode 15 or later.
2. Target **QuantTerminal** → *Signing & Capabilities*: pick your **Team** and change the bundle
   identifier `com.quant.terminal` to one you own (e.g. `com.<you>.quant`).
3. Keep the **Push Notifications** capability (already in `QuantTerminal.entitlements`) and add
   **Background Modes → Remote notifications** if Xcode asks (already in `Info.plist`).
4. Run on the simulator (no account needed) or on your iPhone (free or paid account).
   Push notifications need a real device and a paid Apple Developer account.

## Connect it to your server

The app talks to the quant-terminal-web API (`api` service of its docker compose). That service
listens on `127.0.0.1:8000` on purpose; reach it from the phone through a VPN such as Tailscale
(`http://100.x.y.z:8000` is accepted) or put it behind HTTPS.

```bash
# on the server, with the operator token from .env
curl -X POST https://your-server/api/v1/devices -H "Authorization: Bearer $TERMINAL_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' -d '{"name":"My iPhone"}'
# → {"device": {...}, "token": "qtd_…"}   the token is shown once; only its SHA-256 is stored
```

In the app: **Ajustes** → server URL → paste the `qtd_…` token (saved in the Keychain, this device
only) → **Activar notificaciones**. Revoke a lost phone with
`DELETE /api/v1/devices/{device_id}` (operator token).

## Push alerts (APNs)

1. In the Apple Developer portal create an **APNs Auth Key** (`.p8`); note its Key ID and your Team ID.
2. On the server, mount the `.p8` read-only (never commit it) and set in `.env`:
   `TERMINAL_APNS_KEY_PATH`, `TERMINAL_APNS_KEY_ID`, `TERMINAL_APNS_TEAM_ID` and
   `TERMINAL_APNS_TOPIC` (= your bundle identifier).
3. The `alerts` service (`quant-alerts`) pushes warnings and critical alerts to every device that
   registered a token. Debug builds register as `sandbox`, release builds as `production`; tokens
   APNs reports as gone are cleared.

## Status

The network layer is built and tested on Linux (Swift 6.0.3) in the session that created it; the
iOS app target is compiled by `.github/workflows/ios.yml` on GitHub's macOS runners. It has not
been run on a physical device or signed yet — that needs your Apple account.
