# Hopcast native SDKs 0.7.0 — public API reference

*iOS `HopcastKit` 0.7.0 · Android SDK 0.6.0 · Watch Together and the SDK key kill
switch are iOS 0.7.0 additions: see § 10 and § 11.
Integration guide (iOS): [README](../README.md#3-integration-guide). Migrating from iOS 0.4.1:
[README § 4](../README.md#4-migrating-from-041).*

## 0. Contract

- **Stable.** Every public name listed here is the 0.7.0 API (iOS; Android 0.6.0). Patch releases (0.7.x) only add; they never rename,
  remove or change the meaning of an entry.
- **No break from the previous public releases** (iOS 0.4.1, Android 0.5.2): every public declaration of those
  releases still exists with the same signature. Deprecations and behaviour changes: § 9.
- **One automatic mode, no transport to choose.** The SDK picks the link: Bluetooth LE for discovery, wake-up,
  messages and small files; it switches silently to peer-to-peer Wi-Fi for large files whenever the peer can be
  reached that way (iPhone ↔ iPhone: Network.framework / AWDL; Android ↔ Android: Wi-Fi Direct, Wi-Fi Aware as
  fallback). iPhone ↔ Android uses Bluetooth only (files up to the Bluetooth cap) (§ 2).
- **The SDK imposes its requirements.** It never degrades silently: a missing integration requirement
  (`Info.plist` key, manifest permission, foreground service, API level) is reported by `build()` as a typed
  error naming each missing item, and the device-to-device engine is not started (§ 7).
- **The SDK proposes, the app decides.** The SDK exposes what each neighbor can do right now (links, file size
  limit, whether Wi-Fi can come, foreground state) and reports precise outcomes (typed refusals, typed failure
  reasons). It holds no product policy: compressing a file under the Bluetooth cap, waiting for Wi-Fi, sending to
  fewer recipients, cancelling the remaining copies of a message are app decisions.
- **Naming.** Same concepts, same names on both platforms; each language keeps its conventions
  (`camelCase` enum cases in Swift, `UPPER_SNAKE` in Kotlin; labelled arguments in Swift).
- **Threading.** Every listener is called on the main thread on both platforms.
- **Gating.** Until `provision(…)` succeeded once, the SDK is inert: D2D, online and reporting calls no-op
  (`trySendFiles` returns `refused(notReady)` / `Refused(NOT_READY)`).

## 1. Cross-platform equivalence table

### 1.1 Identity, lifecycle, integration requirements

| Concept | iOS (Swift, `enum HopcastSDK`) | Android (Kotlin, `object HopcastSDK`) |
|---|---|---|
| Enrol the device once | `provision(sdkKey:userId:completion:)` | `provision(sdkKey, userId) { result -> }`, `provision(context, sdkKey, userId, cb)` |
| Enrolled? | `isProvisioned: Bool` | `isProvisioned: Boolean` |
| Forget identity | `clearIdentity()` | `clearIdentity()` |
| Backend device id | `deviceUuid: String` | `deviceUuid: String` |
| Build (once per process) | `builder(deviceId:cacheDirectory:)…build()` | `Builder(deviceId, context, lifecycleOwner?, cacheDir)…build()` |
| Build, throwing on a missing requirement (**new**) | `buildOrThrow() throws` (throws `HopcastIntegrationError`) | `buildOrThrow()` (throws `HopcastIntegrationException`) |
| Missing requirements after `build()` (**new**) | `integrationError: HopcastIntegrationError?` | `integrationError: HopcastIntegrationException?` |
| What is missing (**new**) | `HopcastIntegrationError.missing: [IntegrationRequirement]` | `HopcastIntegrationException.missing: List<IntegrationRequirement>` |
| Requirement kinds (**new**) | `IntegrationRequirement`: `.infoPlistKey(String)`, `.backgroundMode(String)`, `.bonjourService(String)` | `IntegrationRequirement`: `ManifestPermission(permission)`, `ForegroundService(service, type)`, `MinApiLevel(required, actual)` |
| Requirements to declare | `requiredPermissions: [String]` (Info.plist keys) | `getRequiredPermissions(): List<String>` (runtime permissions) |
| Runtime permissions still to request (**new**) | — (iOS prompts by itself on first use) | `getMissingPermissions(): List<String>` |
| Release everything | `release()` (also clears `integrationError`) | `release()` (same) |
| Configured mode | `mode: Mode` | `mode: Mode` |
| Effective links (diagnostics, read-only) | `offlineTransport: OfflineTransport?` | `offlineTransport: OfflineTransport` |
| Start / stop offline radios | `enableOfflineMode()` / `disableOfflineMode()`, `startSharing(listener:)` / `stopSharing()` | same names |
| Start / stop online subsystem | `enableOnlineMode()` / `disableOnlineMode()` | same names |

While `integrationError` is set: no engine exists; `startSharing`, `enableOfflineMode`, `enableOnlineMode` do
nothing, `trySendFiles` returns `refused(notReady)`, `sendFiles` returns `nil` / `null`, `connectedPeers` is
empty. Provisioning keeps working. Fix the integration and relaunch.
Android: a runtime permission the user has not granted yet is **not** an integration error; the engine is built
and the app requests `getMissingPermissions()` before `startSharing()`.

### 1.2 Builder (configuration)

| Option | iOS | Android | Default |
|---|---|---|---|
| Service id (peers must match) | `setServiceId(_:)` | `setServiceId(…)` | bundle id / package name |
| Bluetooth file cap (bytes) | `setBluetoothMaxFileBytes(_: Int)` | `setBluetoothMaxFileBytes(Long)` / `(Int)` | 262 144 (256 KiB), clamped to 0…2 097 152; `0` = never send files over Bluetooth |
| Auto-accept connections | `setAutoAcceptConnections(_:)` | `setAutoAcceptConnections(…)` | `false` |
| Auto-accept transfers | `setAutoAcceptTransfers(_:)` | `setIncomingTransferPolicy(…)` (+ deprecated `setAutoAcceptTransfers`) | manual |
| Mode / online config | `setMode(_:)`, `setOnlineConfig(_:)` | `setMode(…)`, `setOnlineConfig(…)` | `offlineOnly` / `OFFLINE_ONLY` |
| Telemetry endpoint | `setTelemetryEndpoint(url:appToken:)` | `setTelemetryEndpoint(url, appToken)` | none |
| iOS only: Wi-Fi fetch on a Bluetooth wake | `setBackgroundWifiUpgrade(_:)` | — | `true` |
| Android only | — | `setTrustStore`, `setTransferWatchdog`, `setContentProvider`, `setOnSyncEventListener`, `setOnWifiStateChangedListener`, `setAutoDisconnectAfterTransfer` | see the Android SDK documentation |

There is no transport option. `setOfflineTransport` is a deprecated migration escape hatch documented only in
the migration notes (§ 9).

### 1.3 Discovery, connection, peers

| Concept | iOS | Android |
|---|---|---|
| Neighbor list (full snapshot) | `DeviceDiscoveryListener.onNeighborsChanged(_:)` via `setDeviceDiscoveryListener(_:)` | `DeviceDiscoveryListener.onNeighborsChanged(neighbors)` |
| Neighbor | `struct Neighbor { endpointId, displayName }` | `data class Neighbor(endpointId, displayName)` |
| Connect | `inviteNeighbors(endpointIds:)`, `acceptInvitation(endpointId:)`, `rejectInvitation(endpointId:)` | `inviteNeighbors(…)`, `acceptInvitation(…)`, `rejectInvitation(…)` |
| Connection events | `ConnectionListener` (`onIncomingConnectionRequest`, `onConnectionStateChanged`), `setConnectionListener(_:tag:)` | same |
| Connected right now | `connectedPeers: [Neighbor]` (**new**) | `connectedPeers: List<Neighbor>` |
| Capabilities of a peer | `peerInfo(endpointId:) -> PeerInfo?` | `peerInfo(endpointId): PeerInfo?` |
| Capability changes | `PeerLinksListener.onPeerLinksChanged(_:)`, `setPeerLinksListener(_:tag:)` | `PeerLinksListener.onPeerLinksChanged(peer)`, `setPeerLinksListener(…)` |
| Android only | — | `disconnect(endpointId)`, `setNeighborArrivalListener`, `isTransferInProgress`, `activeTransfers`, `isWifiEnabled()` |

`ConnectionState` (iOS): `discovering`, `initiated`, `onHold`, `established`, `rejected`, `disconnected`.

`PeerInfo` (same fields on both platforms):

| Field | Type (iOS / Android) | Meaning |
|---|---|---|
| `neighbor` | `Neighbor` | same `endpointId` as in `onNeighborsChanged` |
| `platform` | `PeerPlatform` `.ios/.android/.unknown` / `IOS/ANDROID/UNKNOWN` | announced by the peer over Bluetooth (Network.framework peers are iPhones) |
| `links` | `Set<PeerLink>` `.wifi/.bluetooth` / `WIFI/BLUETOOTH` | links established now |
| `wifiCapabilities` | `Set<String>` | Wi-Fi technologies the peer offers: `wifi:nw` (iPhone), `wifi:p2p` (Wi-Fi Direct), `wifi:aware` (Wi-Fi Aware) |
| `maxFileBytes` | `Int64?` / `Long?` | largest total size sendable **now**; `nil`/`null` = no limit (Wi-Fi channel open). Over Bluetooth = `min(local cap, peer cap)` |
| `canUpgradeToWifi` (**new**) | `Bool` / `Boolean` | `true`: a Wi-Fi channel is open or can be brought up with this peer, so a send above `maxFileBytes` **waits for Wi-Fi**. `false` (iPhone ↔ Android, Wi-Fi off, Android API < 29): a send above `maxFileBytes` is refused with `tooLargeForBluetooth` |
| `isForeground` | `Bool` / `Boolean` | peer app in the foreground (last state announced by the peer) |
| `alias` (**new**) | `String?` | human name announced by the peer when `neighbor.displayName` is a technical id (§ 8); `nil` otherwise. UI: `alias ?? neighbor.displayName` |

### 1.4 Sending

| Concept | iOS | Android |
|---|---|---|
| Send files, typed result | `trySendFiles(endpointIds:files:metadata:) -> SendFilesResult` | `trySendFiles(endpointIds, files, metadata, disconnectAfterTransfer?): SendFilesResult` |
| Send files, legacy | `sendFiles(endpointIds:files:metadata:) -> String?` | `sendFiles(…): String?` (+ overload with `disconnectAfterTransfer`) |
| Result | `enum SendFilesResult { case started(transferId:), refused(SendRefusalReason) }`, `var transferId: String?` | `sealed class SendFilesResult { Started(transferId), Refused(reason) }`, `val transferIdOrNull: String?` |
| Refusal reasons | `SendRefusalReason`: `notReady`, `sourceUnreadable`, `noConnectedRecipient`, `tooLargeForBluetooth` | `NOT_READY`, `SOURCE_UNREADABLE`, `NO_CONNECTED_RECIPIENT`, `TOO_LARGE_FOR_BLUETOOTH` |
| Cancel (sender or receiver, any state) | `cancelTransfer(transferId:)` | `cancelTransfer(transferId)` |
| Small messages (≤ 24 000 bytes) | `sendBytes(endpointIds:bytes:) -> Bool` | `sendBytes(endpointIds, bytes): Boolean` |
| Receive small messages | `setOnAppBytesReceivedListener(_:tag:)`, `OnAppBytesReceivedListener` (typealias of `AppBytesListener`) `.onAppBytesReceived(from:bytes:)` | `setOnAppBytesReceivedListener(…)`, `OnAppBytesReceivedListener.onAppBytesReceived(fromPeer, bytes)` |

### 1.5 Receiving and transfer events

| Concept | iOS | Android |
|---|---|---|
| Listener | `TransferListener` (`onTransferInvitation`, `onTransferStateChanged`, `onTransferEvent`), `setTransferListener(_:tag:)` | same |
| Accept / reject an invitation | `acceptTransfer(transferId:)`, `rejectTransfer(transferId:)` | same |
| Invitation | `TransferInvitation { transferId, sender, files, totalBytes, customMetadata }` | same fields |
| File descriptor | `TransferFileInfo { id, name, size, mimeType }` | same |
| States | `TransferState`: `idle, invited, accepted, inProgress, finished, cancelled, failed` | `TRANSFER_IDLE … TRANSFER_FAILED` |
| Events | `TransferEvent`: `transferProgress`, `fileProgress`, `fileCompleted`, `fileFailed`, `transferFailed` | same five + Android-only `BulkSendStarted`, `BulkSendFinished` |
| Receiver: "a large payload waits for you" | `PendingPayloadListener.onPendingPayload(_:)`, `PendingPayload` (`expiresAt: Date`) | `PendingPayloadListener.onPendingPayload(pending)`, `PendingPayload` (`expiresAtMs: Long`) |
| Sender: "your send waits for Wi-Fi" (**new**, default no-op) | `PendingPayloadListener.onOutgoingPendingPayload(transferId:recipient:expiresAt:upgrade:)` | `PendingPayloadListener.onOutgoingPendingPayload(transferId, recipient, expiresAtMs, upgrade)` |
| Register | `setPendingPayloadListener(_:tag:)` | `setPendingPayloadListener(…)` |
| Online / reporting | `OnlineEventListener`, `TransferHandoffListener`, `reportDownloadedFile`, `reportRemovedFile`, `declareNeed`, `cancelNeed`, `handleFcmMessage`, `handleFcmToken` | same names |

### 1.6 Failure reasons (`TransferErrorReason`)

| iOS | Android | Emitted when |
|---|---|---|
| `peerDisconnected` | `PEER_DISCONNECTED` | the recipient / sender left during the transfer |
| `invitationRejected` | `INVITATION_REJECTED` | the receiver rejected (`rejectTransfer`, or refused a payload waiting for Wi-Fi) |
| `sourceUnreadable` | `SOURCE_UNREADABLE` | the source file disappeared or became unreadable **after** the transfer started |
| `storageFailure` | `STORAGE_FAILURE` | the receiver could not write the file |
| `payloadFailure` | `PAYLOAD_FAILURE` | link or stream failure, or no progress for 10 s (progress watchdog) |
| `tooLargeForBluetooth` (**new**) | `TOO_LARGE_FOR_BLUETOOTH` (**new**) | too large for Bluetooth and no Wi-Fi possible, found out after the send (§ 3.2) |
| `cancelled` | `CANCELLED` | cancelled through the API |
| `connectionTimeout` (**new on iOS**) | `CONNECTION_TIMEOUT` | the Wi-Fi channel awaited for a large send never came up before expiry (10 min) |
| — | `STALLED` | Android, deprecated migration escape hatch only (`setTransferWatchdog`) |
| `backendError`, `controlChannelError` | `BACKEND_ERROR`, `CONTROL_CHANNEL_ERROR` | online mode |
| `unknown` | `UNKNOWN` | unclassified |

The form used in exchange reports and handoffs is the Swift case name on both platforms
(`connectionTimeout`, `tooLargeForBluetooth`…).

## 2. Links (chosen by the SDK)

| Pair | Discovery, wake-up, `sendBytes`, files ≤ cap | Larger files |
|---|---|---|
| iPhone ↔ iPhone | Bluetooth LE (Wi-Fi when a channel is open) | Network.framework (AWDL, TLS-PSK): a Bluetooth announcement wakes the peer, the file leaves when the Wi-Fi channel opens (foreground, or the ~25 s background wake window) |
| Android ↔ Android (API 29+) | Bluetooth LE (Wi-Fi when a channel is open) | Wi-Fi Direct (Wi-Fi Aware as fallback), negotiated over Bluetooth, no user dialog |
| iPhone ↔ Android | Bluetooth LE | **none**: refused up front (`tooLargeForBluetooth`) |

One neighbor per phone whatever the number of links. A 0.6.0 phone sees neither a 0.4.1 iPhone
(MultipeerConnectivity) nor a 0.5.2 Android phone (Nearby): see § 9 and the
[iOS migration notes](../README.md#4-migrating-from-041).

## 3. Sending semantics

### 3.1 Route decided per recipient before anything is created

| Case (per recipient) | `sendBytes` | `trySendFiles` |
|---|---|---|
| Wi-Fi channel open | Wi-Fi | `started`, files over Wi-Fi |
| Bluetooth only, total ≤ `maxFileBytes` | Bluetooth | `started`, invitation and files over Bluetooth |
| Bluetooth only, total > `maxFileBytes`, `canUpgradeToWifi` | Bluetooth | `started`, **waits for Wi-Fi**: the peer is woken over Bluetooth (receiver: `onPendingPayload`), the sender gets `onOutgoingPendingPayload` (state stays `invited`), the invitation leaves over Wi-Fi when the channel opens (≤ 10 min; `connectionTimeout` / `CONNECTION_TIMEOUT` at expiry) |
| Bluetooth only, total > `maxFileBytes`, not `canUpgradeToWifi` (iPhone ↔ Android) | Bluetooth | **`refused(tooLargeForBluetooth)` / `Refused(TOO_LARGE_FOR_BLUETOOTH)`**: no transfer, no event. One such recipient refuses the whole send |
| Not connected | `false` | `refused(noConnectedRecipient)` |

`total` is the sum of all files of the call. The app reads `peerInfo(endpointId).maxFileBytes` and
`canUpgradeToWifi` **before** sending to decide (e.g. recompress an image under the cap for an Android peer, or
accept to wait for Wi-Fi with an iPhone), and gets the same answer as a typed refusal.

### 3.2 "Too large for Bluetooth": every way the app is told

| When | Signal |
|---|---|
| Before sending | `peerInfo(endpointId).maxFileBytes` + `canUpgradeToWifi == false` |
| At the send, `trySendFiles` | `refused(tooLargeForBluetooth)` / `Refused(TOO_LARGE_FOR_BLUETOOTH)`: nothing created, no event |
| At the send, legacy `sendFiles` | returns a transfer id, then for **every** recipient `failed` + `transferFailed(tooLargeForBluetooth)` (nothing left the device), so apps that only listen to events learn the reason |
| After the send started | `failed` + `transferFailed(tooLargeForBluetooth)` when: the recipient answers that it cannot bring Wi-Fi up (e.g. its Wi-Fi is off); a recipient still linked over Bluetooth stops offering any shared Wi-Fi technology while the send waits; the Wi-Fi channel is lost after the invitation and the file would have to go over Bluetooth |

Never a silent stall, never a generic `payloadFailure` for this cause. A recipient that **disconnects** while
the send waits for Wi-Fi keeps its chance until expiry (`connectionTimeout`).

### 3.3 `trySendFiles` outcomes

- `started(transferId)` / `Started(transferId)`: the outcome arrives through the `TransferListener`
  (`finished`, `transferFailed(reason)`, `cancelled`), per recipient.
- `refused(reason)` / `Refused(reason)`: nothing was created, nothing left the device, **no event follows**.
- `sendFiles` returns `nil` / `null` on any refusal, except `tooLargeForBluetooth` (§ 3.2).

### 3.4 `cancelTransfer`

Valid for all recipients and all sender-side states: waiting for acceptance, waiting for Wi-Fi (the
Bluetooth announcement is withdrawn), in flight (the Wi-Fi file stream is aborted; a small Bluetooth file already
queued may still leave, its completion is ignored). The SDK then reports `cancelled` / `TRANSFER_CANCELLED`
once per recipient and **nothing else** for that transfer, so the app may delete the source file right after.
Unknown or finished id: no-op.

### 3.5 Limits

| Limit | Value |
|---|---|
| Files over Bluetooth | 256 KiB per send by default (sum of files), configurable 0…2 MiB; effective = min of both sides. 256 KiB take 7–20 s on an established link |
| End-to-end padding | the cap applies to the bytes the SDK sends. An app that encrypts and pads (e.g. size buckets) must size the plaintext so that the **padded ciphertext** stays under the cap |
| `sendBytes` | ≤ 24 000 bytes per call |
| Pending payload metadata | `customMetadata` > 2 048 bytes is not carried by the Bluetooth announcement (`PendingPayload.customMetadata == nil`); it still arrives with the invitation |
| Bluetooth links | 8 simultaneous |
| Pending payload lifetime | 10 min |
| Progress watchdog | 10 s without progress → `payloadFailure` |

## 4. Large payloads waiting for Wi-Fi

**Receiver** — `onPendingPayload(PendingPayload)`, delivered **once per `transferId`**, also when iOS relaunched
the app in the background for Bluetooth: the moment to post a local notification. Fields: `transferId`, `sender`,
`totalBytes`, `fileCount`, `mimeType`, `customMetadata`, `preferredWifi` (`"nw"`, `"p2p"`, `"aware"`),
`expiresAt` / `expiresAtMs`, `upgrade` (`inProgress` / `deferredUntilForeground` / `unavailable`). The regular
invitation (same `transferId`) follows over Wi-Fi.

**Sender** — `onOutgoingPendingPayload(transferId, recipient, expiresAt, upgrade)`: once per recipient when the
send is parked waiting for Wi-Fi (`inProgress` until the recipient answers), again if the recipient answers that
it waits for its foreground (`deferredUntilForeground`). An iPhone receiver in the background gets a ~25 s window
on the Bluetooth wake during which Wi-Fi runs (`setBackgroundWifiUpgrade`, default on); otherwise the transfer
leaves when it returns to the foreground, within the 10 min.

## 5. Platform-specific APIs (no counterpart, by design)

- **iOS**: `setBackgroundWifiUpgrade` (Network.framework window on a Bluetooth wake), `HopcastIdentityError`
  (`notProvisioned`, `invalidResponse`, `server(statusCode:)`).
- **Android**: `HopcastService` + `NotificationParameters` + `ServiceActions` (foreground service),
  `getMissingPermissions()`, `isWifiEnabled()`, `HopcastIdentityException`, and features of the deprecated
  migration escape hatch (auto-sync `ContentProvider` / `SyncEvent`, `TrustStore` and `IncomingTransferPolicy`,
  `setTransferWatchdog`, bulk sends, `setAutoDisconnectAfterTransfer`, `disconnect`). See the Android SDK
  documentation.

## 6. Differences on purpose

- **Result helpers**: `SendFilesResult.transferId` (Swift optional) vs `transferIdOrNull` (Kotlin idiom; a
  `transferId` property on the sealed base would clash with `Started.transferId`).
- **Dates**: `expiresAt: Date` vs `expiresAtMs: Long`.
- **Errors**: `HopcastIntegrationError` (Swift `Error`) vs `HopcastIntegrationException` (Kotlin exception),
  like `HopcastIdentityError` / `HopcastIdentityException`.

## 7. Integration requirements (checked by `build()`)

| iOS (`Info.plist`) | Android |
|---|---|
| `NSBluetoothAlwaysUsageDescription` (non-empty) → `.infoPlistKey` | device API level ≥ 26 → `MinApiLevel(26, actual)` |
| `UIBackgroundModes` contains `bluetooth-central` and `bluetooth-peripheral` → `.backgroundMode` | Bluetooth, Wi-Fi, location (API ≤ 32), `NEARBY_WIFI_DEVICES` (API 33+), foreground-service permissions in the merged manifest (declared by the SDK; missing only if removed) → `ManifestPermission(name)` |
| `NSLocalNetworkUsageDescription` (non-empty) → `.infoPlistKey` | a service with `android:foregroundServiceType="connectedDevice"` (e.g. the SDK's `HopcastService`, or the app's own), checked on API 29+ → `ForegroundService(service, type)` |
| `NSBonjourServices` contains `_<serviceId>._tcp` → `.bonjourService` | runtime permissions not granted yet: **not** an integration error, see `getMissingPermissions()` |

`HopcastIntegrationError.description` reads, for example:
`Hopcast SDK integration incomplete — missing: Info.plist: NSBluetoothAlwaysUsageDescription; Info.plist: UIBackgroundModes must contain bluetooth-peripheral`.

Lifecycle rules:
- iOS: build the SDK and register listeners in `application(_:didFinishLaunchingWithOptions:)` on **every**
  launch (also background relaunches by CoreBluetooth state restoration), before returning.
- Android: build once per process (Application or service), request the runtime permissions before
  `startSharing()`, keep the process alive with the `connectedDevice` foreground service for background
  operation. API 26–28: Bluetooth only (no dialog-free Wi-Fi Direct below API 29): `canUpgradeToWifi` is
  `false` and large files are refused with `tooLargeForBluetooth`.
- `build()` twice returns the existing instance; configuration changes after the first `build()` are ignored
  (after an integration error, `build()` checks again).

## 8. Display name in online / hybrid modes

In `onlineOnly` / `hybrid`, a phone advertises its backend device id (`dev_…`) as `Neighbor.displayName`: the
cloud orchestrator matches peers on it. The name given to the Builder travels next to it and is read with
`peerInfo(endpointId).alias`. In `offlineOnly`, `displayName` is already that name and `alias` is `nil`. When a
peer's app is relaunched, the SDK retires the stale instance within ~3 s instead of showing a duplicate until the
liveness timeout.

## 9. Changes since the previous public releases

**Additions** (iOS since 0.4.1; Android since 0.5.2): automatic Bluetooth LE + Wi-Fi mode;
`setBluetoothMaxFileBytes`; `peerInfo`, `PeerInfo` (with `canUpgradeToWifi`, `alias`), `PeerPlatform`,
`PeerLink`, `PeerLinksListener`; `PendingPayloadListener` (with `onOutgoingPendingPayload`), `PendingPayload`;
`trySendFiles`, `SendFilesResult`, `SendRefusalReason`; `TransferErrorReason.tooLargeForBluetooth` /
`TOO_LARGE_FOR_BLUETOOTH`; `integrationError`, `buildOrThrow`, `HopcastIntegrationError` /
`HopcastIntegrationException`, `IntegrationRequirement`; `offlineTransport` (read-only); iOS: `sendBytes`,
`setOnAppBytesReceivedListener`, `OnAppBytesReceivedListener`, `setBackgroundWifiUpgrade`, `connectedPeers`,
`TransferErrorReason.connectionTimeout`; Android: `getMissingPermissions()`.

**Deprecated** (still compile, with a warning):
- `Builder.setOfflineTransport(…)`: the SDK chooses the links. Kept only as a migration escape hatch during a
  mixed-version rollout (iOS `.both` / `.multipeer` to reach 0.4.1 iPhones, see the
  [iOS migration notes](../README.md#4-migrating-from-041); Android `NEARBY` to reach 0.5.2 phones). These values
  give up Bluetooth and cross-platform discovery.
- iOS `setAppBytesListener(_:tag:)` / `removeAppBytesListener(tag:)`: aliases of
  `setOnAppBytesReceivedListener(_:tag:)` / `removeOnAppBytesReceivedListener(tag:)`.
- Android (unchanged since 0.5.2): `Builder.setAutoAcceptTransfers` → `setIncomingTransferPolicy`;
  `setTransferHandoffListener(listener)` → `setTransferHandoffListener(listener, tag)`.

**Breaking changes**: none in signatures. Source and behaviour notes:
- New enum cases: `TransferErrorReason.tooLargeForBluetooth` (both), `connectionTimeout` (iOS). Swift:
  `HopcastKit.xcframework` is built with library evolution, a `switch` over an SDK enum needs `@unknown default`
  (already the case with 0.4.1). Kotlin: an exhaustive `when` over `TransferErrorReason` used as an expression
  needs an `else ->` branch.
- Links: iOS 0.4.1 used MultipeerConnectivity, Android 0.5.2 used Nearby Connections. 0.6.0 uses the automatic
  Bluetooth + Wi-Fi mode and sees neither (escape hatches above).
- Integration requirements are enforced (§ 7) instead of degrading silently.
- Sender-side terminal outcome per recipient: a recipient that rejects the invitation gets `failed` +
  `transferFailed(invitationRejected)` (0.4.1 / 0.5.2: `cancelled` without reason); a recipient that disconnects
  during a send always gets `failed` + `transferFailed(peerDisconnected)`. Other recipients of a
  multi-recipient send continue.

## 10. Watch Together (iOS `HopcastKit` 0.7.0)

Nearby devices watch **one media in sync**. One device **hosts** a local file or an HTTP(S) stream; nearby
devices get an **invitation**, **join**, open a local playback URL in the app's own player and follow the shared
play, pause, seek and rate. Any participant can control playback. Everything is added in the `WatchTogether*`
namespace plus one `Builder` flag; the 0.6.x API is unchanged. Full guide:
<https://docs.hopcast.io/platforms/watch-together/>.

- **Opt-in.** Off by default: `HopcastSDK.Builder.setWatchTogetherEnabled(_ enabled: Bool) -> HopcastSDK.Builder`
  (set it on every launch, in the same `build()`). A device that does not enable it neither takes part in nor
  announces sessions. No new `Info.plist` key.
- **Gating** (first failing condition decides): SDK key revoked → `WatchTogetherError.sdkDisabled`; not
  provisioned → `notProvisioned`; flag missing, SDK not built or `integrationError` set → `notEnabled`.
  `WatchTogether.isAvailable` tells whether `host` and `join` can run now. The device-to-device engine must be
  running (`startSharing(listener:)`).
- **Threading.** Entry points and every callback are on the main thread.
- **Automatic connections.** While a device hosts, takes part in or listens for sessions, the SDK connects to
  nearby Watch Together devices by itself (`onIncomingConnectionRequest` is not called for them).

### 10.1 Entry points

```swift
public enum WatchTogether {
    public static let maxMetadataBytes: Int            // 16 * 1024
    public static var isAvailable: Bool { get }
    public static var currentSession: WatchTogetherSession? { get }
    public static var invitations: [WatchTogetherInvitation] { get }

    @discardableResult
    public static func host(source: WatchTogetherSource, media: WatchTogetherMedia,
                            options: WatchTogetherOptions = WatchTogetherOptions(),
                            listener: WatchTogetherListener?) throws -> WatchTogetherSession

    public static func setInvitationListener(_ listener: WatchTogetherInvitationListener?) throws

    @discardableResult
    public static func join(_ invitation: WatchTogetherInvitation,
                            options: WatchTogetherOptions = WatchTogetherOptions(),
                            listener: WatchTogetherListener?) throws -> WatchTogetherSession
}
```

| Member | Behaviour |
|---|---|
| `host` | Starts a session from this device; the session is `.preparing` until the playback URL is ready. `.file` is checked immediately (`fileNotFound`, `emptyFile`); an `.http` origin is checked before the session is announced (failure: `.ended(.failed(.sourceUnreachable))` / `.rangeNotSupported`). Throws `alreadyInSession`, `metadataTooLarge` and the gating errors. Listeners are held weakly. |
| `setInvitationListener` | Starts (non-`nil`) or stops (`nil`) listening for nearby sessions. |
| `join` | Joins a nearby session. Throws `invitationExpired` if the invitation is gone, `alreadyInSession`, or a gating error. |
| `currentSession` | The session this device takes part in (one at a time), `nil` once it ended. |
| `invitations` | Nearby sessions currently known. |

### 10.2 Sources, media and options

```swift
public enum WatchTogetherSource { case file(URL); case http(WatchTogetherHTTPSource) }

public struct WatchTogetherHTTPSource {
    public var url: URL                      // must honour byte ranges (206 Partial Content)
    public var headers: [String: String]     // sent only to this origin, never shared, never logged
    public var sourceGroupId: String?        // same value = devices may share the download; nil = private
    public init(url: URL, headers: [String: String] = [:], sourceGroupId: String? = nil)
}

public struct WatchTogetherMedia {
    public var title: String
    public var duration: TimeInterval?
    public var contentType: String?          // nil: derived from the file extension
    public var metadata: Data?               // opaque app payload, <= WatchTogether.maxMetadataBytes
    public init(title: String, duration: TimeInterval? = nil, contentType: String? = nil, metadata: Data? = nil)
}

public struct WatchTogetherOptions {
    public var cacheDirectory: URL?          // default: the app's Caches
    public var keepCacheOnEnd: Bool          // default false
    public var serverSource: ((WatchTogetherSessionInfo) -> WatchTogetherHTTPSource?)?
    public var probesUnknownDevices: Bool    // default true
    public init()
}
```

`serverSource` lets a guest of a server stream use **its own** URL and credentials for the same media (return
`nil` to rely on nearby devices only); it has the same effect as `WatchTogetherSession.enableServerSource`.

### 10.3 The session

```swift
public final class WatchTogetherSession {
    public let sessionId: String
    public let role: WatchTogetherRole                    // .host / .guest
    public weak var listener: WatchTogetherListener?
    public var state: WatchTogetherState { get }
    public var isMaster: Bool { get }                     // this device currently leads playback
    public var playbackURL: URL? { get }                  // local URL for the player, valid for this session only
    public var info: WatchTogetherSessionInfo? { get }
    public var participants: [WatchTogetherParticipant] { get }
    public var counters: WatchTogetherByteCounters { get }
    public var stats: WatchTogetherStats { get }

    public func attach(player: PlayerClock)
    public func detach()
    public func play()
    public func pause()
    public func seek(to seconds: TimeInterval)
    public func setRate(_ rate: Float)                    // 0 < rate <= 4
    public func enableServerSource(_ source: WatchTogetherHTTPSource,
                                   completion: ((WatchTogetherError?) -> Void)? = nil)
    public func claimMaster()
    public func resumeAfterForeground()
    public func leave()
    public func end()
}
```

- Open `playbackURL` in the player first, then `attach(player:)`: the session drives play, pause, seek and small
  rate corrections.
- `play()`, `pause()`, `seek(to:)`, `setRate(_:)` apply **for everyone** and can be called by any participant.
- `claimMaster()` takes the lead back (for example the original host returning).
- `resumeAfterForeground()`: call it when the app becomes active again.
- `leave()` leaves (the others keep watching); `end()` ends the session for everyone.
- If the leading device leaves, locks or goes out of range, playback continues, the state is `.hostLost`, and
  another participant takes the lead within seconds (`masterChanged`).

### 10.4 Types, state and errors

```swift
public struct WatchTogetherInvitation: Hashable {
    public let sessionId: String, hostName: String, hostEndpointId: String, title: String
    public let metadata: Data?, duration: TimeInterval?, isServerStream: Bool, sourceGroupId: String?
}
public struct WatchTogetherSessionInfo: Equatable {
    public let sessionId: String, title: String, contentType: String, size: Int64
    public let metadata: Data?, duration: TimeInterval?, isServerStream: Bool, sourceGroupId: String?
}
public struct WatchTogetherParticipant: Hashable {
    public let id: String, name: String
    public let isLocal: Bool, isHost: Bool, isMaster: Bool, isConnected: Bool, isServerCapable: Bool
    public let progress: Double?                          // share of the media held, 0...1
}
public enum WatchTogetherRole: Equatable { case host, guest }

public enum WatchTogetherState: Equatable {
    case preparing, active, hostLost, needsServerOrSamePlatformPeer
    case ended(WatchTogetherEndReason)
}
public enum WatchTogetherEndReason: Equatable { case left, endedByHost, sdkDisabled, failed(WatchTogetherError) }

public enum WatchTogetherError: Error, Equatable {
    case notProvisioned, sdkDisabled, notEnabled, alreadyInSession
    case fileNotFound, emptyFile, sourceUnreachable, rangeNotSupported, sizeMismatch
    case invitationExpired, wrongRole, storage, metadataTooLarge
}
```

| State | Meaning |
|---|---|
| `.preparing` | Host: checking the source. Guest: joining. |
| `.active` | Playing together (or ready to). |
| `.hostLost` | The leading device is unreachable; playback continues and another participant takes the lead shortly unless it returns. |
| `.needsServerOrSamePlatformPeer` | This device cannot receive the media (no same-platform device nearby over a fast link, no HTTP origin enabled here). Playback control still works. |
| `.ended(reason)` | Final. `.sdkDisabled`: the SDK key was revoked or the SDK released. |

Keep an `@unknown default` in `switch` statements over these public enums.

### 10.5 Player integration

```swift
public protocol PlayerClock: AnyObject {
    var currentTime: TimeInterval { get }
    var isPlaying: Bool { get }
    var isBuffering: Bool { get }          // default implementation: false
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func setRate(_ rate: Float)
}

public final class WatchTogetherCoarseClock {
    public init()
    public func report(_ seconds: TimeInterval)
    public func setPlaying(_ playing: Bool)
    public func setRate(_ rate: Double)
    public func didSeek(to seconds: TimeInterval)
    public var currentTime: TimeInterval { get }
    public var isStalled: Bool { get }
}
```

`PlayerClock` is called on the main thread. `setRate` is used for small corrections **while playing** and must
not change the play/pause state. `WatchTogetherCoarseClock` smooths players that report their time a few times
per second (such as VLCKit): feed it every report and read `currentTime` from your `PlayerClock`.

### 10.6 Listeners and events

```swift
public protocol WatchTogetherListener: AnyObject {
    func onStateChanged(_ session: WatchTogetherSession, state: WatchTogetherState)
    func onPlaybackURLReady(_ session: WatchTogetherSession, url: URL)
    func onSessionInfo(_ session: WatchTogetherSession, info: WatchTogetherSessionInfo)
    func onParticipantsChanged(_ session: WatchTogetherSession, participants: [WatchTogetherParticipant])
    func onEvent(_ session: WatchTogetherSession, event: WatchTogetherEvent)
}

public protocol WatchTogetherInvitationListener: AnyObject {
    func onInvitation(_ invitation: WatchTogetherInvitation)
    func onInvitationWithdrawn(_ invitation: WatchTogetherInvitation)
}

public enum WatchTogetherEvent: Equatable {
    case participantJoined(id: String, name: String)
    case participantLeft(id: String)
    case hostLost, hostRecovered
    case masterChanged(participantId: String, isLocal: Bool)
    case stalled(seconds: Double)
    case resynced
    case serverSourceEnabled
    case serverSourceFailed(WatchTogetherError)
    case complete                                  // this device holds the whole media
}
```

Every listener method has an empty default implementation and is called on the main thread.

### 10.7 Counters and statistics

`WatchTogetherSession.counters` returns `WatchTogetherByteCounters` (`peerReceived`, `peerSent`,
`serverReceived`: bytes moved by this device since the session started). `WatchTogetherSession.stats` returns a
`WatchTogetherStats` for a dashboard, refreshed regularly: `time`, `participants: [WatchTogetherPeerStats]` (per
participant: `partsHeld`, `bufferedAhead`, `position`, `isPlaying`, `driftMs`, `stalls`, `bytes`, `departed`,
`progress`) and `flows: [WatchTogetherFlow]` (bytes and bits per second from one participant, or from
`WatchTogetherFlow.originId` for the HTTP origin, to another).

### 10.8 Limits

- Media data moves between devices only over fast local links; a device reachable only over Bluetooth gets
  playback control but no media.
- Mixed iPhone / Android sessions: each platform needs one device with server access to the media or a
  same-platform device that holds it.
- One session per device at a time. Sources: a local file, or an HTTP(S) origin that honours byte ranges.

## 11. SDK key kill switch (iOS `HopcastKit` 0.7.0)

When the backend revokes the SDK key embedded in a build, the SDK shuts down for good: every public API becomes
a silent no-op, its credentials are purged, the local reporting queue is kept and the app is notified once.

```swift
public enum SdkDisabledReason: String, Equatable, Sendable { case sdkKeyRevoked }

public protocol SdkDisabledListener: AnyObject {
    func onSdkDisabled(reason: SdkDisabledReason)         // main thread, once
}

HopcastSDK.isDisabled                                      // Bool
HopcastSDK.setSdkDisabledListener(_ listener: SdkDisabledListener?)   // set before build()
HopcastIdentityError.sdkDisabled                           // returned by provision with a revoked key
```

A build that ships a **new** SDK key brings the SDK back through `provision(sdkKey:userId:completion:)`. The
notification is not replayed when the process starts already disabled: read `isDisabled`. An expired token is
refreshed at SDK start and when connectivity returns, so a revoked device that touches the network is shut down
within about 24 hours.
