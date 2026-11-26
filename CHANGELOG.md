# Changelog

## 0.7.0 — 2026-11-TBD

### Highlights

- **Watch Together.** Nearby devices watch **one media in sync**. One device hosts a local file or an HTTP(S)
  stream; nearby devices get an invitation ("Alice is watching *Movie* — Join"), join, open a local playback
  URL in the app's own player and follow the shared play, pause, seek and rate. Any participant can control
  playback.
- **The media is shared between nearby devices.** For a server stream, the origin is downloaded about once for
  the whole group; for a local file, guests receive copies from nearby devices. Received media is checked for
  corruption.
- **The session survives the leading device.** If the device that leads playback leaves, locks or goes out of
  range, playback continues and another participant takes the lead within seconds. The original host can come
  back and take the lead again.
- **Credentials stay on the device.** HTTP headers given for an origin are sent only to that origin, never to
  other participants, never logged. Each guest can use its own URL and credentials for the same media.
- **Player-agnostic.** `PlayerClock` drives AVPlayer, VLCKit or any other player; `WatchTogetherCoarseClock`
  smooths players that report their time coarsely.
- **Dashboard and energy accounting.** `session.stats` and `session.counters`.
- **Opt-in.** Off by default; enable it with `HopcastSDK.Builder.setWatchTogetherEnabled(true)`. Requires
  provisioning.
- **Also ships the SDK key kill switch (planned 0.6.1, never published separately).** When the backend revokes
  the SDK key, the SDK shuts down for good, purges its credentials and notifies the app once. New:
  `HopcastSDK.isDisabled`, `HopcastSDK.setSdkDisabledListener(_:)`, `SdkDisabledReason`,
  `HopcastIdentityError.sdkDisabled`. A build shipping a new SDK key brings the SDK back through `provision`.

### API additions

New, namespaced `WatchTogether*`: `WatchTogether` (`host`, `join`, `setInvitationListener`, `invitations`,
`currentSession`, `isAvailable`), `WatchTogetherSession`, `WatchTogetherSource` / `WatchTogetherHTTPSource`,
`WatchTogetherMedia`, `WatchTogetherOptions`, `WatchTogetherInvitation`, `WatchTogetherSessionInfo`,
`WatchTogetherParticipant`, `WatchTogetherState`, `WatchTogetherEndReason`, `WatchTogetherError`,
`WatchTogetherEvent`, `WatchTogetherListener`, `WatchTogetherInvitationListener`, `PlayerClock`,
`WatchTogetherCoarseClock`, `WatchTogetherByteCounters`, `WatchTogetherPeerStats`, `WatchTogetherFlow`,
`WatchTogetherStats`, `HopcastSDK.Builder.setWatchTogetherEnabled(_:)`. Kill switch: `HopcastSDK.isDisabled`,
`setSdkDisabledListener(_:)`, `SdkDisabledListener`, `SdkDisabledReason`, `HopcastIdentityError.sdkDisabled`.
Reference: [docs/API.md](docs/API.md) § 10.

### Compatibility

- **The 0.6.x API is unchanged**: no declaration was removed or changed. An app that does not call
  `setWatchTogetherEnabled(true)` behaves exactly as on 0.6.x, and the device does not take part in nor announce
  Watch Together.
- **No new `Info.plist` key.** The 0.6.0 requirements (Bluetooth, local network, Bonjour service, background
  modes) are enough.
- Devices on 0.6.x keep exchanging files and messages with 0.7.0 devices as before; they do not take part in
  Watch Together sessions.
- While a device hosts, takes part in or listens for Watch Together sessions, the SDK connects to nearby Watch
  Together devices automatically.
- Public enums are not frozen: keep `@unknown default`.

### Known limits

- **Data between devices only over fast local links.** A device reachable only over Bluetooth gets playback
  control but no media.
- **Mixed iPhone / Android sessions**: each platform needs one device with server access to the media or a
  same-platform device that holds it. Playback control works across platforms.
- One session per device at a time. Sources: a local file, or an HTTP(S) origin that honours byte ranges.
- Watch Together is a foreground feature: call `resumeAfterForeground()` when the app becomes active again.
- Validated on simulators and on two real iPhones (local file, pause / resume / seek, host leaving, shared
  server stream). Not yet validated on real devices: more than two devices, long background suspension, and
  sessions mixing iPhone and Android.

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
