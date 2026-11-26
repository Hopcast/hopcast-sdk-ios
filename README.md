# Hopcast iOS SDK

Hopcast adds **peer-assisted content delivery** to your iOS app: nearby devices exchange
your app's content and messages directly, device-to-device, instead of going through your
servers. The SDK picks the link by itself: **Bluetooth LE** for discovery, wake-up,
messages and small files, and **peer-to-peer Wi-Fi** (Network.framework / AWDL) for large
files between iPhones. It keeps working **in the background, with the screen locked and
after iOS terminated your app**, and talks to Android phones running the Hopcast Android
SDK 0.6.0. iOS 0.7.0 adds **Watch Together**: nearby devices watch one media in sync. On top of this device-to-device layer, an optional **online mode** lets the
Hopcast cloud match devices that *have* a content with devices that *need* it, and
trigger the transfer automatically. Every exchange is reported to your Hopcast dashboard.

**What's new in 0.7.0**

- **Watch Together.** Nearby devices watch **one media in sync**: one device hosts a local file or an
  HTTP(S) stream, nearby devices get an invitation, join and follow the shared play, pause, seek and
  rate in the app's own player (AVPlayer, VLCKit, any player through `PlayerClock`). Opt-in with
  `Builder.setWatchTogetherEnabled(true)`; see [Watch Together](#312-watch-together-070).
- **SDK key kill switch.** `HopcastSDK.isDisabled`, `setSdkDisabledListener(_:)`, `SdkDisabledReason`,
  `HopcastIdentityError.sdkDisabled` (planned for 0.6.1, shipped with 0.7.0).
- **The 0.6.x API is unchanged**, no new `Info.plist` key. See [CHANGELOG.md](CHANGELOG.md).

**What's new in 0.6.0**

- **One automatic mode, nothing to choose.** Bluetooth LE + peer-to-peer Wi-Fi replace
  MultipeerConnectivity. Discovery and links survive background, screen lock and system
  termination (CoreBluetooth state restoration relaunches your app).
- **iPhone ↔ Android.** Discovery, small messages (`sendBytes`) and files up to the
  Bluetooth cap work across platforms.
- **The SDK checks its requirements.** `build()` verifies your `Info.plist`; if anything is
  missing it does not start and tells you exactly what to add
  (`HopcastSDK.integrationError`, `buildOrThrow()`).
- **The SDK proposes, the app decides.** `peerInfo(endpointId:)` tells you what each
  neighbor can receive right now; `trySendFiles` returns a typed result instead of `nil`;
  failure reasons are precise per recipient.
- **Large payloads wait for Wi-Fi instead of failing**, with callbacks on both sides
  (`PendingPayloadListener`).
- New APIs: `sendBytes` / `setOnAppBytesReceivedListener` (small messages),
  `setBluetoothMaxFileBytes`, `setBackgroundWifiUpgrade`, `connectedPeers`,
  `PeerLinksListener`. No 0.4.1 declaration was removed or changed; see
  [Migrating from 0.4.1](#4-migrating-from-041).

**This repository contains:**

| Path | Content |
|---|---|
| `Package.swift` | Swift Package manifest — the compiled SDK (device + simulator) is downloaded from this repository's GitHub Releases (`HopcastKit.xcframework.zip`, checksum-verified by SPM) |
| `Example/` | A complete SwiftUI example app |
| `docs/API.md` | Full API reference |
| `CHANGELOG.md` | Release history |

Requirements: **iOS 14+**, Xcode 15+. The example app targets iOS 16.
Device-to-device transfers need **physical devices** (not the simulator).

---

## 1. Installation

In Xcode: **File → Add Package Dependencies…**, paste:

```
https://github.com/Hopcast/hopcast-sdk-ios
```

and add the `HopcastKit` product to your app target. Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Hopcast/hopcast-sdk-ios", from: "0.6.0")
]
```

Then, in code:

```swift
import HopcastKit
```

All SDK entry points live on the `HopcastSDK` facade.

---

## Getting your SDK key

Your SDK key (`pk_live_…`) is obtained from your Hopcast account management console at
**https://console.hopcast.io**. It is designed to be embedded in your app and can be
revoked at any time from the console.

---

## 2. Try the example app first (recommended)

`Example/HopcastExample.xcodeproj` is a ready-to-run SwiftUI app that demonstrates the
full integration. You need **two physical iPhones** (device-to-device transfers do not
work in the simulator) and an SDK key (see *Getting your SDK key* above).

1. Open `Example/HopcastExample.xcodeproj`, select your development team, and run the
   app on both iPhones.
2. On first launch, enter your SDK key to enroll each device (once per install).
3. **Device-to-device flow**: on the *Dashboard* tab, nearby devices appear under
   "Nearby devices". Connect to one, create a demo content, long-press it and send it to
   the neighbor.
4. **Online flow**: enable the "Online mode" toggle on both devices. On device A,
   create a demo content (it is declared to Hopcast automatically). On device B, request
   that content id in the "Needs" section. Within seconds Hopcast orchestrates the
   transfer from A to B automatically — no user interaction.
5. The *Journal* tab shows every SDK callback as it happens; the *Settings* tab shows
   the device identity and connection status.

The app's source (`Example/Sources/`) is intentionally small and heavily commented:

- `HopcastController.swift` — the one place that builds the SDK, provisions the device
  and implements every listener. **Start reading here.**
- `Views/DashboardView.swift` — discovery, contents, needs UI.
- `Views/SettingsView.swift` — identity and connection status.

---

## 3. Integration guide

### 3.1 Info.plist (mandatory, checked by `build()`)

The SDK needs **all** of the following entries in your app's `Info.plist`. `build()`
checks them; if one is missing, it does **not** start the device-to-device engine and
reports a typed error naming exactly what is missing. There is no silent fallback.

| # | `Info.plist` key | Value | Reported as |
|---|---|---|---|
| 1 | `NSBluetoothAlwaysUsageDescription` | non-empty text | `.infoPlistKey("NSBluetoothAlwaysUsageDescription")` |
| 2 | `UIBackgroundModes` | contains `bluetooth-central` | `.backgroundMode("bluetooth-central")` |
| 3 | `UIBackgroundModes` | contains `bluetooth-peripheral` | `.backgroundMode("bluetooth-peripheral")` |
| 4 | `NSLocalNetworkUsageDescription` | non-empty text | `.infoPlistKey("NSLocalNetworkUsageDescription")` |
| 5 | `NSBonjourServices` | contains `_<serviceId>._tcp` | `.bonjourService("_<serviceId>._tcp")` |

`<serviceId>` is the normalized value you pass to `setServiceId(_:)` (lowercase letters,
digits and `-`, at most 15 characters). Two devices only see each other if their apps use
the same service id.

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>$(PRODUCT_NAME) uses Bluetooth to exchange content with nearby phones, without a network.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>$(PRODUCT_NAME) uses the local network to send files to nearby phones.</string>
<key>NSBonjourServices</key>
<array>
  <string>_myservice._tcp</string>
</array>
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
  <string>bluetooth-peripheral</string>
</array>
```

- `HopcastSDK.requiredPermissions` lists these keys at runtime.
- Background modes are plain `Info.plist` keys: no entitlement is needed, a wildcard
  provisioning profile is enough.
- iOS shows the Bluetooth and Local Network prompts on first use; there is no runtime API
  to call. A user who refuses Bluetooth is a runtime state, not an integration error: the
  SDK keeps running and simply finds no peer.
- Local notifications (`UNUserNotificationCenter`) are your app's job: request
  authorization while in the foreground.

Checking the result:

```swift
do {
    try HopcastSDK.builder(deviceId: "Alice", cacheDirectory: cache)
        .setServiceId("myservice")
        .buildOrThrow()
} catch let error as HopcastIntegrationError {
    // e.g. "… missing: Info.plist: NSBluetoothAlwaysUsageDescription; Info.plist: UIBackgroundModes must contain bluetooth-peripheral"
    assertionFailure("Hopcast integration incomplete: \(error.missing)")
} catch {}
// or: HopcastSDK.builder(…).build(); if let error = HopcastSDK.integrationError { … }
```

While `integrationError` is set, `startSharing` / `enableOfflineMode` /
`enableOnlineMode` do nothing and `trySendFiles` returns `.refused(.notReady)`.
Provisioning keeps working. Fix the `Info.plist` and relaunch.

### 3.2 Enroll the device (once)

Call `provision` after your user's first sign-in, while the device is online. This is a
one-time operation: the resulting device identity is stored in the Keychain and survives
app restarts, offline periods and reinstalls that preserve the Keychain.

```swift
HopcastSDK.provision(sdkKey: "pk_live_…", userId: user.id) { result in
    switch result {
    case .success:
        // The device is enrolled; the SDK is now operational:
        // call HopcastSDK.startSharing(listener:) now (see 3.3).
        break
    case .failure(let error):
        // Show a retry path — the SDK stays inert until provisioning succeeds.
        print("Hopcast provisioning failed: \(error)")
    }
}
```

**The SDK is inert until provisioned**: every other API safely no-ops
(`trySendFiles` returns `.refused(.notReady)`). Check `HopcastSDK.isProvisioned` to
decide whether to call `provision` again (calling it when already provisioned succeeds
immediately, without any network call). After that single enrollment, device-to-device
exchanges work without any internet connection.

`HopcastSDK.clearIdentity()` drops the identity (for account switching or tests);
re-provision afterwards.

### 3.3 Build the SDK at every launch

iOS may relaunch your app **in the background** for a Bluetooth event (state
restoration). Build the SDK and register your listeners in
`application(_:didFinishLaunchingWithOptions:)`, **on every launch, before returning**,
otherwise the event that woke the app is lost. In a SwiftUI app, use
`UIApplicationDelegateAdaptor`.

```swift
import UIKit
import HopcastKit

final class AppDelegate: NSObject, UIApplicationDelegate, PendingPayloadListener, OnAppBytesReceivedListener,
                         TransferListener, DeviceDiscoveryListener {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hopcast", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        HopcastSDK.builder(deviceId: "Alice", cacheDirectory: cache)
            .setServiceId("myservice")
            // .setBluetoothMaxFileBytes(262_144)    // default; 0 = never send files over Bluetooth
            .setAutoAcceptConnections(true)
            .build()
        if let error = HopcastSDK.integrationError {
            assertionFailure("Hopcast integration incomplete: \(error.missing)")   // see 3.1
            return true
        }
        HopcastSDK.setPendingPayloadListener(self, tag: "app")
        HopcastSDK.setOnAppBytesReceivedListener(self, tag: "app")
        HopcastSDK.setTransferListener(self, tag: "app")
        if HopcastSDK.isProvisioned { HopcastSDK.startSharing(listener: self) }
        return true
    }

    func onNeighborsChanged(_ neighbors: [Neighbor]) {
        HopcastSDK.inviteNeighbors(endpointIds: neighbors.map(\.endpointId))
    }

    /// Receiver: a large payload waits for Wi-Fi (also on a background Bluetooth wake).
    func onPendingPayload(_ pending: PendingPayload) { /* post a local notification */ }

    /// Sender: this send waits for Wi-Fi with that recipient (iPhone peer).
    func onOutgoingPendingPayload(transferId: String, recipient: Neighbor, expiresAt: Date,
                                  upgrade: PendingPayload.Upgrade) { /* show "waiting for Wi-Fi" */ }

    func onAppBytesReceived(from peer: Neighbor, bytes: Data) { /* small message, ≤ 24 000 bytes */ }

    func onTransferEvent(_ event: TransferEvent) {
        if case .transferFailed(let id, _, .tooLargeForBluetooth, let peer) = event {
            print("\(id) too large for Bluetooth with \(peer.displayName)")   // e.g. offer a smaller version
        }
    }

    /// The app decides what to do; the SDK only reports what is possible.
    func send(_ file: URL, to peer: Neighbor) {
        switch HopcastSDK.trySendFiles(endpointIds: [peer.endpointId], files: [file]) {
        case .started(let transferId):
            print("started \(transferId)")             // outcome arrives through TransferListener
        case .refused(.tooLargeForBluetooth):
            // Android peer (no Wi-Fi between iPhone and Android): shrink below the cap, or do not send.
            let cap = HopcastSDK.peerInfo(endpointId: peer.endpointId)?.maxFileBytes ?? 262_144
            print("shrink below \(cap) bytes")
        case .refused(let reason):
            print("not sent: \(reason)")               // notReady, sourceUnreadable, noConnectedRecipient
        @unknown default:
            break                                      // binary framework: required in Swift 6 mode
        }
    }
}
```

Builder options:

| Option | Default | Notes |
|---|---|---|
| `setServiceId(_:)` | bundle id | Peers must match; drives `NSBonjourServices` (3.1) |
| `setBluetoothMaxFileBytes(_:)` | 262 144 (256 KiB) | Clamped to 0…2 097 152; `0` = never send files over Bluetooth |
| `setBackgroundWifiUpgrade(_:)` | `true` | Fetch a large payload over Wi-Fi during the ~25 s background wake window (3.6) |
| `setAutoAcceptConnections(_:)` | `false` | `true`: incoming connections are accepted without `onIncomingConnectionRequest` |
| `setAutoAcceptTransfers(_:)` | `false` | `true`: incoming transfers are accepted without `onTransferInvitation` |
| `setMode(_:)` | `.offlineOnly` | `.offlineOnly`, `.onlineOnly`, `.hybrid` (3.7) |
| `setOnlineConfig(_:)` | none | Required for `.onlineOnly` / `.hybrid` |
| `setTelemetryEndpoint(url:appToken:)` | none | Optional telemetry endpoint |

Notes:

- `deviceId` is the human-readable name shown to neighbors. `cacheDirectory` is where
  received files are written and, in online mode, where the SDK looks up files by
  content id when this device serves content (**the file name is the content id**).
- `build()` twice returns the existing instance; configuration changes after the first
  `build()` are ignored (after an integration error, `build()` checks again).
- Listeners are registered under a `tag` so different components can observe
  independently, and can be replaced at any time. **All callbacks are delivered on the
  main thread.**
- The code above compiles as is in the Swift 5 language mode. In the **Swift 6 language
  mode**, the listener protocols carry no actor annotation yet: declare main-actor
  conformances `@preconcurrency` (`…, @preconcurrency PendingPayloadListener,
  @preconcurrency OnAppBytesReceivedListener, …`).
- Keep `@unknown default` in every `switch` over an SDK enum (the framework is built with
  library evolution, and enums may gain cases in minor releases).

### 3.4 What the SDK chooses for you

| Peer | Discovery, messages, files ≤ cap | Larger files |
|---|---|---|
| iPhone (0.6.0) | Bluetooth LE, or Wi-Fi when a channel is open | Peer-to-peer Wi-Fi (Network.framework / AWDL, TLS-PSK): the send **waits for Wi-Fi** (`onOutgoingPendingPayload`); the peer is woken over Bluetooth and the file leaves when the Wi-Fi channel opens (≤ 10 min) |
| Android (0.6.0) | Bluetooth LE | **Refused** with `tooLargeForBluetooth`: there is no Wi-Fi between iPhone and Android |

Before sending, `peerInfo(endpointId:)` tells your app what will happen:

| `PeerInfo` field | Meaning |
|---|---|
| `neighbor` | Same `endpointId` as in `onNeighborsChanged` |
| `platform` | `.ios`, `.android`, `.unknown` |
| `links` | `Set<PeerLink>` established now: `.bluetooth`, `.wifi` |
| `wifiCapabilities` | Wi-Fi technologies the peer offers (e.g. `wifi:nw` for an iPhone) |
| `maxFileBytes` | Largest total size sendable **now**; `nil` = no limit (Wi-Fi channel open). Over Bluetooth: the smaller cap of both sides |
| `canUpgradeToWifi` | `true`: a send above `maxFileBytes` waits for Wi-Fi. `false`: it is refused with `tooLargeForBluetooth` |
| `isForeground` | The peer app is in the foreground |
| `alias` | Human name announced by the peer in online / hybrid mode (see 3.7); `nil` otherwise |

`PeerLinksListener.onPeerLinksChanged(_:)` (registered with
`setPeerLinksListener(_:tag:)`) notifies you when these values change.

"Too large for Bluetooth" always reaches your app explicitly:

| When | Signal |
|---|---|
| Before sending | `peerInfo(endpointId:)?.maxFileBytes` + `canUpgradeToWifi == false` |
| At the send, `trySendFiles` | `.refused(.tooLargeForBluetooth)`: nothing is created, no event follows |
| At the send, legacy `sendFiles` | a transfer id, then for every recipient `.failed` + `transferFailed(reason: .tooLargeForBluetooth)` |
| After the send started (recipient's Wi-Fi off, Wi-Fi lost) | `.failed` + `transferFailed(reason: .tooLargeForBluetooth)` |

### 3.5 Discovery, connection, sending and receiving

Start and stop the radios (requires a provisioned device and no `integrationError`):

```swift
HopcastSDK.startSharing(listener: discoveryListener)   // or enableOfflineMode() + setDeviceDiscoveryListener(_:)
HopcastSDK.stopSharing()                               // or disableOfflineMode()
```

**Discovery.** Nearby devices running your app appear through the discovery listener,
which always receives the full current snapshot (an empty list means no neighbor is
reachable). There is one neighbor per phone, whatever the number of links:

```swift
func onNeighborsChanged(_ neighbors: [Neighbor]) { }   // neighbor.endpointId, neighbor.displayName
```

**Connection.** Connect to a discovered neighbor (both sides get callbacks through
`ConnectionListener`, registered with `setConnectionListener(_:tag:)`):

```swift
HopcastSDK.inviteNeighbors(endpointIds: [neighbor.endpointId])

// Receiver side, unless setAutoAcceptConnections(true):
func onIncomingConnectionRequest(neighbor: Neighbor) {
    HopcastSDK.acceptInvitation(endpointId: neighbor.endpointId)   // or rejectInvitation(endpointId:)
}
func onConnectionStateChanged(state: ConnectionState, neighbor: Neighbor) { }
```

`HopcastSDK.connectedPeers` returns the neighbors connected right now.

**Send small messages** (at most 24 000 bytes per call), received through
`OnAppBytesReceivedListener.onAppBytesReceived(from:bytes:)`:

```swift
let accepted = HopcastSDK.sendBytes(endpointIds: [endpointId], bytes: Data("hello".utf8))
```

`sendBytes` returns `false` when the payload is too big or no recipient is connected.

**Send files** to one or more connected neighbors with `trySendFiles` (see the example in
3.3). The total of all files of the call is compared with each recipient's
`maxFileBytes`; one recipient that would refuse with `tooLargeForBluetooth` refuses the
whole send. `.started(transferId:)` means the outcome (`finished`,
`transferFailed(reason:)` or `cancelled`) arrives per recipient through the
`TransferListener`; `.refused(reason)` means nothing was created and no event follows.
The legacy `sendFiles(endpointIds:files:metadata:)` still exists and returns the transfer
id or `nil`.

**Receive files.** The receiver gets a transfer invitation (unless
`setAutoAcceptTransfers(true)`):

```swift
func onTransferInvitation(_ invitation: TransferInvitation) {
    // invitation.sender, invitation.files ([TransferFileInfo]), invitation.totalBytes, invitation.customMetadata
    HopcastSDK.acceptTransfer(transferId: invitation.transferId)   // or rejectTransfer(transferId:)
}
```

**Cancel.** Either side can cancel with `HopcastSDK.cancelTransfer(transferId:)`, in any
sender-side state (waiting for acceptance, waiting for Wi-Fi, in flight). The SDK then
reports `cancelled` once per recipient and nothing else for that transfer, so your app may
delete the source file right after. An unknown or finished id is a no-op.

### 3.6 Large payloads waiting for Wi-Fi

Between iPhones reachable only over Bluetooth, a send above `maxFileBytes` is not refused:
it **waits for Wi-Fi** (at most 10 minutes).

- **Receiver** — `PendingPayloadListener.onPendingPayload(_:)` is delivered **once per
  `transferId`**, including when iOS relaunched the app in the background for Bluetooth:
  the right moment to post a local notification. `PendingPayload` carries `transferId`,
  `sender`, `totalBytes`, `fileCount`, `mimeType`, `customMetadata` (`nil` above
  2 048 bytes; it still arrives with the invitation), `preferredWifi`, `expiresAt` and
  `upgrade` (`.inProgress`, `.deferredUntilForeground`, `.unavailable`). The regular
  invitation, with the same `transferId`, follows over Wi-Fi.
- **Sender** — `onOutgoingPendingPayload(transferId:recipient:expiresAt:upgrade:)` (default
  no-op) is called once per recipient when the send is parked waiting for Wi-Fi
  (`.inProgress`), and again if the recipient answers that it waits for its foreground
  (`.deferredUntilForeground`). The transfer state stays `.invited` meanwhile; if the Wi-Fi
  channel never opens, the transfer fails with `connectionTimeout`.
- A receiver in the background gets a **~25 s window** on the Bluetooth wake during which
  peer-to-peer Wi-Fi runs (`setBackgroundWifiUpgrade`, default `true`, best effort);
  otherwise the file is fetched when the app returns to the foreground.

Register the listener with `HopcastSDK.setPendingPayloadListener(_:tag:)`.

### 3.7 Online mode — automatic, cloud-orchestrated

Build with `.setMode(.onlineOnly)` or `.setMode(.hybrid)` and
`.setOnlineConfig(OnlineConfig())`, then activate it when your app is ready (and
deactivate it freely):

```swift
HopcastSDK.enableOnlineMode()
HopcastSDK.disableOnlineMode()
```

Register an `OnlineEventListener` with `setOnlineEventListener(_:tag:)`:
`onCloudReady(deviceUuid:)` fires when the device is connected and available for
orchestration; `onCloudDisconnected()` when it is not (the SDK reconnects automatically).

**Declare inventory.** Tell Hopcast which contents this device holds, so it can serve
them to nearby devices. Call this after your own downloads complete, and on app start
for contents already on disk:

```swift
// infraType = how the content was obtained: .wifi, .cellular, .d2d or .stored
HopcastSDK.reportDownloadedFile(infraType: .wifi, contentIds: ["episode-1044"])

// When you delete a content from your cache:
HopcastSDK.reportRemovedFile(contentIds: ["episode-1044"])
```

Contents received through Hopcast itself are declared automatically.

**Request content.** When this device wants a content, file a *need*:

```swift
if let needId = HopcastSDK.declareNeed(contentId: "episode-1044", ttlSeconds: 300) {
    // Later, if the user navigates away / the need is obsolete:
    HopcastSDK.cancelNeed(needId: needId)
}
```

If a nearby device has the content, Hopcast triggers the transfer automatically:

- The receiving side gets `onFilesToBeDownloaded(fileIds:)` (a heads-up that a delivery
  is starting), then regular `TransferListener` progress events, and the file lands in
  `cacheDirectory` named after its content id.
- The sending side just serves the file; you don't have to do anything.
- `onCloudError(reason:)` reports orchestration failures (e.g. the peer went out of
  range) — the cloud retries on its own while the need is valid.

Online transfers are always accepted automatically, whatever `setAutoAcceptTransfers`
says.

**Display names.** In `.onlineOnly` / `.hybrid`, a phone advertises its backend device id
as `Neighbor.displayName` (the cloud matches peers on it). The name you gave the builder
travels next to it: show `HopcastSDK.peerInfo(endpointId:)?.alias ?? neighbor.displayName`.

**Push wake-ups (optional but recommended).** If your app uses Firebase Cloud
Messaging, forward the token and data messages so Hopcast can wake your app when a
delivery is scheduled while it is in the background:

```swift
// In MessagingDelegate:
HopcastSDK.handleFcmToken(fcmToken)
// In your data-message handler:
HopcastSDK.handleFcmMessage(message.data)   // ignores messages that aren't Hopcast's
```

### 3.8 Observing transfers and reporting

`TransferListener` covers every transfer, whether it was started by your app or by the
cloud — the `transferId` is the common key:

```swift
// Same transferId on both sides; isReceiver tells you which side you are on.
func onTransferStateChanged(transferId: String, isReceiver: Bool,
                            state: TransferState, peer: Neighbor) { }
func onTransferEvent(_ event: TransferEvent) { }   // progress, per-file completion, failures
```

`TransferState`: `idle`, `invited`, `accepted`, `inProgress`, `finished`, `cancelled`,
`failed`. `TransferEvent`: `transferProgress`, `fileProgress`, `fileCompleted` (with the
receiver's `localPath`), `fileFailed`, `transferFailed`. Failure reasons
(`TransferErrorReason`): `peerDisconnected`, `invitationRejected`, `sourceUnreadable`,
`storageFailure`, `payloadFailure` (link failure or no progress for 10 s),
`tooLargeForBluetooth`, `connectionTimeout`, `cancelled`, `backendError`,
`controlChannelError`, `unknown`. In a multi-recipient send, each recipient gets its own
outcome and the others continue.

Received files are written to `cacheDirectory`.

Exchange reporting to your Hopcast dashboard is automatic — including which flow
(`online` / `offline`) produced each exchange, transferred bytes and success/failure.
Reports are queued durably on the device (airplane mode, app kills and reboots included)
and delivered when connectivity allows; you have nothing to implement.

### 3.9 Behaviour by app state

| App state | Bluetooth (discovery, links, `sendBytes`, files ≤ cap) | Peer-to-peer Wi-Fi | Large incoming file |
|---|---|---|---|
| Foreground | yes | yes | received over Wi-Fi |
| Background / suspended | **yes**: links stay up, the app is woken by Bluetooth events; discovery is slower | **no** sustained Wi-Fi, except the ~25 s window opened by a Bluetooth wake for a pending payload (`setBackgroundWifiUpgrade`) | `onPendingPayload` delivered once (post a notification); fetched in the 25 s window, otherwise when the app returns to the foreground |
| Screen locked | same as background | same as background | same as background |
| Terminated by the system (memory, update) | **yes**: CoreBluetooth state restoration relaunches the app in the background on a Bluetooth event; the SDK must be built in `didFinishLaunching` (3.3) | as background | as background |
| Force-quit by the user (swipe up) | **no** (Apple's documented behaviour) until the user opens the app again | no | no |

Timers do not run while your app is suspended: the SDK flushes its queues on each
Bluetooth event and on return to the foreground. Do the same for your own send queue
(resend unacknowledged messages in `onPeerLinksChanged` or on foreground, never only on a
timer). When a peer's app is relaunched, its stale entry disappears within ~3 s.

### 3.10 Limits

- **Files over Bluetooth: 256 KiB per send** (sum of all files) by default, configurable
  0…2 MiB with `setBluetoothMaxFileBytes`; the effective cap with a peer is the smaller of
  both sides (`PeerInfo.maxFileBytes`). 256 KiB take 7–20 s on an established link.
- **End-to-end padding**: the cap applies to the bytes the SDK sends. If your app
  encrypts and pads, size the plaintext so that the padded ciphertext stays under the cap.
- iPhone ↔ Android: Bluetooth only. A file above the cap to an Android peer is refused
  with `tooLargeForBluetooth`.
- `sendBytes`: ≤ 24 000 bytes per call. 8 simultaneous Bluetooth links. A payload waiting
  for Wi-Fi is kept 10 min.
- The Bluetooth link is not encrypted: encrypt private content end to end in your app.
  Peer-to-peer Wi-Fi uses TLS-PSK.
- Android advertisements use the Bluetooth SIG test company ID `0xFFFF` (provisional).

### 3.11 Lifecycle

```swift
HopcastSDK.release()    // tears everything down (also clears integrationError); rebuild with the builder to use again
```

### 3.12 Watch Together (0.7.0)

Nearby devices watch **one media in sync**. One device hosts a local file or an HTTP(S) stream; nearby devices
get an invitation, join, open a local playback URL in the app's own player and follow the shared play, pause,
seek and rate. Any participant can control playback, and the session continues if the leading device leaves.
Watch Together is **opt-in** and needs no new `Info.plist` key.

- **Leave vs stop for everyone.** `session.leave()` takes only this device out (the others keep watching; if it
  led, it hands the lead over at once). `session.end()` stops playback for everyone and can be called by any
  participant; the others end with `.ended(.endedBy(participantId:name:))`, e.g. "Léa stopped playback". Offer
  both actions in your UI.
- **Several sessions nearby.** `WatchTogether.invitations` lists every nearby session in discovery order; show
  them all (a list when there are several). `WatchTogetherInvitation.participantCount` gives the number of
  devices in each (`nil` when unknown).

```swift
import HopcastKit

// 1. At every launch, in the same build() as the rest:
HopcastSDK.builder(deviceId: "Alice", cacheDirectory: cache)
    .setServiceId("myservice")
    .setWatchTogetherEnabled(true)            // opt-in
    .build()

// 2. Host a local file (the device must be provisioned and sharing):
final class HostController: WatchTogetherListener {
    private(set) var session: WatchTogetherSession?

    func startHosting(file: URL) {
        let media = WatchTogetherMedia(title: "Holiday video", duration: 5_400, contentType: "video/mp4")
        do {
            session = try WatchTogether.host(source: .file(file), media: media, listener: self)
        } catch {
            print("cannot host: \(error)")      // notProvisioned, notEnabled, fileNotFound, ...
        }
    }

    func onPlaybackURLReady(_ session: WatchTogetherSession, url: URL) {
        // Open `url` in your player, then session.attach(player:) with a PlayerClock adapter.
    }
}

// 3. Show every nearby invitation and join the one the user picks:
try WatchTogether.setInvitationListener(banner)        // WatchTogetherInvitationListener
for invitation in WatchTogether.invitations {          // discovery order
    print(invitation.hostName, invitation.title, invitation.participantCount ?? 0)
}
let session = try WatchTogether.join(invitation, listener: guestController)

// 4. Leave (only this device) or stop for everyone (any participant):
session.leave()
// session.end()   // the others get .ended(.endedBy(participantId:name:))
```

Full guide with complete AVPlayer and VLCKit adapters, server streams and dashboard statistics:
<https://docs.hopcast.io/platforms/watch-together/>. Reference: [docs/API.md § 10](docs/API.md#10-watch-together-ios-hopcastkit-070).

---

## 4. Migrating from 0.4.1

1. Bump the package to `from: "0.6.0"`. No public declaration of 0.4.1 was removed or
   changed.
2. **Add the five `Info.plist` entries of [3.1](#31-infoplist-mandatory-checked-by-build).**
   0.4.1 only needed the local network ones; 0.6.0 refuses to start its engine without
   Bluetooth and its background modes (`HopcastSDK.integrationError`). The
   `_<serviceId>._udp` Bonjour entry is no longer needed.
3. Build the SDK in `application(_:didFinishLaunchingWithOptions:)` on every launch
   ([3.3](#33-build-the-sdk-at-every-launch)).
4. **0.6.0 does not see 0.4.1 phones**: 0.4.1 used MultipeerConnectivity, 0.6.0 uses
   Bluetooth + Network.framework. During a mixed-version rollout only, the deprecated
   escape hatch `.setOfflineTransport(.both)` (Network.framework first,
   MultipeerConnectivity fallback) or `.setOfflineTransport(.multipeer)` keeps talking to
   0.4.1 phones. It gives up Bluetooth (no background, no Android), and its `Info.plist`
   needs become `NSLocalNetworkUsageDescription` + `NSBonjourServices` `_<serviceId>._tcp`
   and `_<serviceId>._udp`. Remove it once every phone runs 0.6.0.
5. Prefer `trySendFiles` to `sendFiles` to get typed refusals; read
   `peerInfo(endpointId:)` before sending media.
6. A rejected invitation now ends, for that recipient, in `.failed` +
   `transferFailed(reason: .invitationRejected)` (0.4.1: `.cancelled`); a recipient
   leaving mid-send always gets `.failed` + `transferFailed(reason: .peerDisconnected)`.
   Update UI code that treated `.cancelled` as "rejected".
7. Keep `@unknown default` in `switch` statements over SDK enums (`TransferErrorReason`
   gained `connectionTimeout` and `tooLargeForBluetooth`).
8. In online / hybrid mode, show `peerInfo(endpointId:)?.alias ?? neighbor.displayName`
   ([3.7](#37-online-mode--automatic-cloud-orchestrated)).

---

## 5. API quick reference

Full reference: [docs/API.md](docs/API.md).

| Area | API |
|---|---|
| Identity | `provision(sdkKey:userId:completion:)`, `isProvisioned`, `clearIdentity()`, `deviceUuid` |
| Setup | `builder(deviceId:cacheDirectory:)` → `setServiceId`, `setBluetoothMaxFileBytes`, `setBackgroundWifiUpgrade`, `setAutoAcceptConnections`, `setAutoAcceptTransfers`, `setMode`, `setOnlineConfig`, `setTelemetryEndpoint`, `build()`, `buildOrThrow()` |
| Integration | `integrationError`, `HopcastIntegrationError.missing`, `IntegrationRequirement`, `requiredPermissions` |
| Modes | `enableOnlineMode()`, `disableOnlineMode()`, `enableOfflineMode()`, `disableOfflineMode()`, `mode`, `offlineTransport` (read-only) |
| Peers | `startSharing(listener:)`, `stopSharing()`, `inviteNeighbors(endpointIds:)`, `acceptInvitation(endpointId:)`, `rejectInvitation(endpointId:)`, `connectedPeers`, `peerInfo(endpointId:)` |
| Sending | `trySendFiles(endpointIds:files:metadata:)`, `sendFiles(endpointIds:files:metadata:)`, `sendBytes(endpointIds:bytes:)`, `acceptTransfer(transferId:)`, `rejectTransfer(transferId:)`, `cancelTransfer(transferId:)` |
| Online | `reportDownloadedFile(infraType:contentIds:)`, `reportRemovedFile(contentIds:)`, `declareNeed(contentId:ttlSeconds:)`, `cancelNeed(needId:)`, `handleFcmToken(_:)`, `handleFcmMessage(_:)` |
| Listeners | `setDeviceDiscoveryListener`, `setConnectionListener`, `setTransferListener`, `setPendingPayloadListener`, `setPeerLinksListener`, `setOnAppBytesReceivedListener`, `setOnlineEventListener`, `setTransferHandoffListener` (+ matching `remove…` calls) |
| Watch Together (0.7.0) | `Builder.setWatchTogetherEnabled(_:)`, `WatchTogether.host(source:media:options:listener:)`, `join(_:options:listener:)`, `setInvitationListener(_:)`, `WatchTogetherSession`, `PlayerClock` |
| Kill switch (0.7.0) | `isDisabled`, `setSdkDisabledListener(_:)`, `SdkDisabledReason` |
| Misc | `release()` |

---

## 6. Troubleshooting

- **Nothing starts, `trySendFiles` returns `.refused(.notReady)`** — check
  `HopcastSDK.integrationError` (missing `Info.plist` entries, see 3.1) and
  `HopcastSDK.isProvisioned` (see 3.2). The release binary does not log: rely on these
  two properties and on the listener callbacks.
- **Devices don't see each other** — both apps must use the same `serviceId`, and
  Bluetooth must be on and allowed (Settings → Privacy & Security → Bluetooth). A 0.6.0
  phone does not see a 0.4.1 phone (see section 4). Transfers require physical devices,
  not simulators.
- **Nothing happens after the user swiped the app away** — expected: iOS does not
  relaunch a force-quit app for Bluetooth until the user opens it again.
- **Events are missed after a background relaunch** — the SDK must be built and the
  listeners registered in `didFinishLaunchingWithOptions`, on every launch (3.3).
- **Large files to an Android phone are refused** — expected (`tooLargeForBluetooth`):
  there is no Wi-Fi between iPhone and Android. Shrink the file below
  `peerInfo(endpointId:)?.maxFileBytes` or do not send it.
- **A large file to an iPhone does not leave** — it waits for Wi-Fi
  (`onOutgoingPendingPayload`); it leaves when the receiver opens a Wi-Fi window (wake
  window or foreground), otherwise it fails with `connectionTimeout` after 10 min. Check
  the Local Network permission on both phones.
- **`declareNeed` returns nil** — the SDK is not provisioned, or the mode does not
  include the online flow.
- **Online transfers don't start** — both devices must have online mode enabled, be
  within D2D range of each other, and the serving device must actually hold the content
  (declared via `reportDownloadedFile`, file present in `cacheDirectory` under the
  content id).
- **Nothing appears on the dashboard** — device reports are batched and sent when
  connectivity allows; they can lag a transfer by a few moments.

## Support

contact@hopcast.io — © Hopcast. See [LICENSE](LICENSE).
