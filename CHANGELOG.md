# Changelog

## 0.6.0 — 2026-11-04

### Highlights

- **One automatic mode, nothing to choose.** Bluetooth LE for discovery, wake-up, messages and small files;
  peer-to-peer Wi-Fi (Network.framework / AWDL, TLS-PSK) for large files between iPhones, switched on silently.
  Phones find and link to each other **in the background, screen locked, and after the system terminated the
  app** (CoreBluetooth state restoration relaunches it).
- **iPhone ↔ Android.** The Bluetooth protocol is shared with the Android SDK 0.6.0: discovery, messages
  (`sendBytes`) and files up to the Bluetooth cap work across platforms. There is no Wi-Fi between iPhone and
  Android: a larger file is refused with a precise reason.
- **The SDK imposes its requirements.** `build()` checks the `Info.plist` (Bluetooth usage, Bluetooth background
  modes, local network usage, Bonjour service) and, if anything is missing, does not start its engine and reports
  `HopcastSDK.integrationError` (`HopcastIntegrationError.missing: [IntegrationRequirement]`), or throws from
  `buildOrThrow()`. No silent fallback.
- **The SDK proposes, the app decides.**
  - `peerInfo(endpointId:)` / `PeerLinksListener`: platform, links, the largest file sendable now
    (`maxFileBytes`), whether a larger one can wait for Wi-Fi (`canUpgradeToWifi`), foreground state, and the
    peer's human name in online / hybrid mode (`alias`).
  - `trySendFiles` → `SendFilesResult` with a typed `SendRefusalReason` (`notReady`, `sourceUnreadable`,
    `noConnectedRecipient`, `tooLargeForBluetooth`): a refused send creates nothing and emits nothing.
  - **"Too large for Bluetooth" is always explicit**: up front (`refused(tooLargeForBluetooth)`), through the
    legacy `sendFiles` (id + `transferFailed(tooLargeForBluetooth)`), and after the start
    (`TransferErrorReason.tooLargeForBluetooth` when the recipient's Wi-Fi is off or Wi-Fi is lost).
  - Precise failure reasons per recipient (`invitationRejected`, `peerDisconnected`, `sourceUnreadable`,
    `connectionTimeout`, `tooLargeForBluetooth`…) and a `cancelTransfer` that covers every sender-side state.
- **Large payloads wait for Wi-Fi instead of failing.** Between iPhones reachable only over Bluetooth, the
  receiver is woken (`onPendingPayload`, once per transfer, also on a background relaunch: post a notification)
  and fetches the file over Wi-Fi in a ~25 s background window (`setBackgroundWifiUpgrade`, default on) or when it
  returns to the foreground; the sender is told (`onOutgoingPendingPayload`).
- New: `sendBytes` + `setOnAppBytesReceivedListener` (≤ 24 000 bytes), `setBluetoothMaxFileBytes`,
  `connectedPeers`, `offlineTransport` (read-only diagnostics).


### Compatibility

- No public declaration of 0.4.1 was removed or changed (checked against the 0.4.1 `.swiftinterface`).
- **Links changed**: 0.4.1 used MultipeerConnectivity; 0.6.0 does not see a 0.4.1 phone. During a mixed-version
  rollout, the deprecated `.setOfflineTransport(.both)` / `.multipeer` keeps talking to 0.4.1 phones (no
  Bluetooth, no Android). See [Migrating from 0.4.1](README.md#4-migrating-from-041).
- **New mandatory `Info.plist` entries** (Bluetooth usage, background modes): without them the engine does not
  start.
- A rejected invitation now ends in `failed` + `transferFailed(invitationRejected)` for that recipient (0.4.1:
  `cancelled`).
- `TransferErrorReason` gains `connectionTimeout` and `tooLargeForBluetooth`; keep `@unknown default`.
- Full list and cross-platform table: [docs/API.md](docs/API.md).

### Integration requirements (checked by `build()`)

`NSBluetoothAlwaysUsageDescription`, `UIBackgroundModes` = `bluetooth-central` + `bluetooth-peripheral`,
`NSLocalNetworkUsageDescription`, `NSBonjourServices` = `_<serviceId>._tcp`. Build the SDK and register the
listeners in `application(_:didFinishLaunchingWithOptions:)` on every launch.

### Known limits

- Files over Bluetooth: **256 KiB per send** by default (0…2 MiB), 7–20 s per 256 KiB. End-to-end padding added by
  the app counts toward the cap.
- No Wi-Fi between iPhone and Android: larger files to an Android peer are refused (`tooLargeForBluetooth`); the
  app shrinks them or gives up.
- No sustained peer-to-peer Wi-Fi in the background (iOS stops Network.framework); only the short wake window.
- A force-quit app (swiped away by the user) is not relaunched by Bluetooth until the user opens it.
- The Bluetooth link is not encrypted (protocol v1); Network.framework uses TLS-PSK. Encrypt private content end to
  end in the app.
- Android advertisements use the Bluetooth SIG test company ID `0xFFFF` (provisional).
- Swift 6 language mode: listener protocols are not actor-annotated yet; use `@preconcurrency` conformances.
- Not measured yet: iPhone ↔ iPhone discovery with both apps in the background for a long time (overflow area),
  meshes larger than 7 links.


## 0.4.1 — 2026-08-18

- Example app fully translated to English.
- README: where to obtain the SDK key (account management console).
- No SDK code change (binary rebuilt as 0.4.1).

## 0.4.0 — 2026-08-18

- First public binary distribution (`HopcastKit.xcframework`).
- Online mode: cloud-orchestrated device-to-device delivery (needs/has, automatic
  transfers, FCM wake-up).
- Offline mode: manual AirDrop-like discovery, connection and file transfer, fully
  functional without internet.
- Exchange reporting for both modes.

The repository ships a complete SwiftUI example app (`Example/`) exercising both modes;
see the README integration guide.
