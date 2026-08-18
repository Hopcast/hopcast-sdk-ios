# Hopcast iOS SDK

Hopcast adds **peer-assisted content delivery** to your iOS app: nearby devices exchange
your app's content directly, device-to-device, instead of re-downloading it from your
servers. Two complementary flows are available:

- **Online mode** — fully automatic. Your app tells Hopcast which contents each device
  *has* and which contents it *needs*; the Hopcast cloud matches nearby devices and the
  SDK performs the transfer in the background. No transfer UI to build.
- **Offline mode** — manual, AirDrop-like, and works **without any internet
  connection**. Your app drives discovery, connection and file sending through the SDK
  and gets callbacks for every step.

Both flows share one device identity, one cache directory and one set of listeners, and
can run side by side (`hybrid` mode). Every exchange is reported to your Hopcast
dashboard, including whether it used the online or offline flow.

**This repository contains:**

| Path | Content |
|---|---|
| `HopcastKit.xcframework` | The SDK — compiled binary framework (device + simulator) |
| `Package.swift` | Swift Package manifest so the repo is consumable via SPM |
| `Example/` | A complete SwiftUI example app exercising both modes |

Requirements: **iOS 14+**, Xcode 15+. The example app targets iOS 16.

---

## 1. Installation

In Xcode: **File → Add Package Dependencies…**, paste:

```
https://github.com/Hopcast/hopcast-sdk-ios
```

and add the `HopcastKit` product to your app target. Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Hopcast/hopcast-sdk-ios", from: "0.4.0")
]
```

Then, in code:

```swift
import HopcastKit
```

All SDK entry points live on the `HopcastSDK` facade.

---

## 2. Try the example app first (recommended)

`Example/HopcastExample.xcodeproj` is a ready-to-run SwiftUI app that demonstrates the
full integration. You need **two physical iPhones** (device-to-device transfers do not
work in the simulator) and a Hopcast SDK key (`pk_live_…`, provided with your account).

1. Open `Example/HopcastExample.xcodeproj`, select your development team, and run the
   app on both iPhones.
2. On first launch, enter your SDK key to enroll each device (once per install).
3. **Offline flow**: on the *Dashboard* tab, nearby devices appear under "Voisins D2D".
   Connect to one, create a demo content, long-press it and send it to the neighbor.
4. **Online flow**: enable the "Mode online" toggle on both devices. On device A,
   create a demo content (it is declared to Hopcast automatically). On device B, request
   that content id in the "Besoins" section. Within seconds Hopcast orchestrates the
   transfer from A to B automatically — no user interaction.
5. The *Journal* tab shows every SDK callback as it happens; the *Réglages* tab shows
   the device identity and connection status.

The app's source (`Example/Sources/`) is intentionally small and heavily commented:

- `HopcastController.swift` — the one place that builds the SDK, provisions the device
  and implements every listener. **Start reading here.**
- `Views/DashboardView.swift` — discovery, contents, needs UI.
- `Views/SettingsView.swift` — identity and connection status.

---

## 3. Integration guide

### 3.1 Info.plist

Device-to-device delivery uses Apple's local networking. Add to your `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>$(PRODUCT_NAME) uses the local network to exchange content with nearby devices.</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>$(PRODUCT_NAME) uses Bluetooth to discover nearby devices.</string>
<key>NSBonjourServices</key>
<array>
  <string>_hopcast._tcp</string>
  <string>_hopcast._udp</string>
</array>
```

iOS shows the local-network permission prompt the first time the SDK starts advertising;
`HopcastSDK.requiredPermissions` lists the required keys at runtime if you want to
assert on them in debug builds.

> The Bonjour service entries must match the `serviceId` you pass to the builder
> (section 3.3): service id `hopcast` ⇒ `_hopcast._tcp` / `_hopcast._udp`. Two devices
> can only discover each other if their apps use the same service id.

### 3.2 Enroll the device (once)

Call `provision` after your user's first sign-in, while the device is online. This is a
one-time operation: the resulting device identity is stored in the Keychain and survives
app restarts, offline periods and reinstalls that preserve the Keychain.

```swift
HopcastSDK.provision(sdkKey: "pk_live_…", userId: user.id) { result in
    switch result {
    case .success:
        // The device is enrolled; the SDK is now operational.
    case .failure(let error):
        // Show a retry path — the SDK stays inert until provisioning succeeds.
    }
}
```

**The SDK is inert until provisioned**: every other API safely no-ops and logs a
warning. Check `HopcastSDK.isProvisioned` to decide whether to call `provision` again
(calling it when already provisioned succeeds immediately, without any network call).

`HopcastSDK.clearIdentity()` drops the identity (for account switching or tests);
re-provision afterwards.

### 3.3 Build the SDK (once per launch)

Configure and build the singleton early — typically in your `App` init or
`application(_:didFinishLaunchingWithOptions:)`:

```swift
HopcastSDK
    .builder(deviceId: UIDevice.current.name,          // human-readable display name
             cacheDirectory: myCacheDirectory)         // where received files land
    .setMode(.hybrid)                                  // .offlineOnly | .onlineOnly | .hybrid
    .setServiceId("hopcast")                           // must match NSBonjourServices
    .setAutoAcceptConnections(false)                   // offline flow: ask the user first
    .setAutoAcceptTransfers(false)                     // offline flow: ask the user first
    .setOnlineConfig(OnlineConfig())                   // required for .onlineOnly / .hybrid
    .build()
```

Notes:

- `cacheDirectory` is both where received files are written and where the online mode
  looks up files by content id when this device serves content. **The file name is the
  content id.**
- `Mode` decides which flows the host can activate at runtime; `hybrid` allows both.
- Auto-accept only affects the *manual* offline flow. Online-mode transfers are always
  automatic.
- Build once; register your listeners right after (they can be replaced at any time):

```swift
HopcastSDK.setDeviceDiscoveryListener(listener)
HopcastSDK.setConnectionListener(listener, tag: "app")
HopcastSDK.setTransferListener(listener, tag: "app")
HopcastSDK.setOnlineEventListener(listener, tag: "app")
```

Listeners are registered under a `tag` so different components can observe
independently; all callbacks are delivered on the main queue.

### 3.4 Online mode — automatic, cloud-orchestrated

Activate it when your app is ready (and deactivate it freely):

```swift
HopcastSDK.enableOnlineMode()
HopcastSDK.disableOnlineMode()
```

`OnlineEventListener.onCloudReady(deviceUuid:)` fires when the device is connected and
available for orchestration; `onCloudDisconnected()` when it is not (the SDK reconnects
automatically).

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
let needId = HopcastSDK.declareNeed(contentId: "episode-1044", ttlSeconds: 300)
// Later, if the user navigates away / the need is obsolete:
HopcastSDK.cancelNeed(needId: needId!)
```

If a nearby device has the content, Hopcast triggers the transfer automatically:

- The receiving side gets `onFilesToBeDownloaded(fileIds:)` (a heads-up that a delivery
  is starting), then regular `TransferListener` progress events, and the file lands in
  `cacheDirectory` named after its content id.
- The sending side just serves the file; you don't have to do anything.
- `onCloudError(reason:)` reports orchestration failures (e.g. the peer went out of
  range) — the cloud retries on its own while the need is valid.

**Push wake-ups (optional but recommended).** If your app uses Firebase Cloud
Messaging, forward the token and data messages so Hopcast can wake your app when a
delivery is scheduled while it is in the background:

```swift
// In MessagingDelegate:
HopcastSDK.handleFcmToken(fcmToken)
// In your data-message handler:
HopcastSDK.handleFcmMessage(message.data)   // ignores messages that aren't Hopcast's
```

### 3.5 Offline mode — manual, works with no internet

Activate the radios:

```swift
HopcastSDK.enableOfflineMode()      // start advertising + browsing
HopcastSDK.disableOfflineMode()     // stop everything, disconnect
```

(`startSharing(listener:)` / `stopSharing()` are equivalent shortcuts that also register
a discovery listener.)

**Discovery.** Nearby devices running your app appear through the discovery listener,
which always receives the full current snapshot (an empty list means no neighbor is
reachable):

```swift
func onNeighborsChanged(_ neighbors: [Neighbor]) { }   // neighbor.endpointId, neighbor.displayName
```

**Connection.** Connect to a discovered neighbor (both sides get callbacks):

```swift
HopcastSDK.inviteNeighbors(endpointIds: [neighbor.endpointId])

// Receiver side (ConnectionListener), unless auto-accept is on:
func onIncomingConnectionRequest(neighbor: Neighbor) {
    HopcastSDK.acceptInvitation(endpointId: neighbor.endpointId)   // or rejectInvitation
}
func onConnectionStateChanged(state: ConnectionState, neighbor: Neighbor) { }
```

**Send files** to one or more connected neighbors:

```swift
let transferId = HopcastSDK.sendFiles(endpointIds: [endpointId],
                                      files: [fileURL1, fileURL2])
```

**Receive files.** The receiver gets a transfer invitation (unless auto-accept is on):

```swift
func onTransferInvitation(_ invitation: TransferInvitation) {
    HopcastSDK.acceptTransfer(transferId: invitation.transferId)   // or rejectTransfer
}
```

Either side can abort an in-flight transfer with
`HopcastSDK.cancelTransfer(transferId:)`.

### 3.6 Observing transfers (both modes)

`TransferListener` covers every transfer, whether it was started manually or by the
cloud — the `transferId` is the common key:

```swift
// Same transferId on both sides; isReceiver tells you which side you are on.
func onTransferStateChanged(transferId: String, isReceiver: Bool,
                            state: TransferState, peer: Neighbor) { }
func onTransferEvent(_ event: TransferEvent) { }   // progress, per-file completion, failures
```

Received files are written to `cacheDirectory`, named after their content id.

Exchange reporting to your Hopcast dashboard is automatic in both modes — including
which flow (`online` / `offline`) produced each exchange, transferred bytes and
success/failure. Reports are queued durably on the device (airplane mode, app kills and
reboots included) and delivered when connectivity allows; you have nothing to implement.

### 3.7 Lifecycle

```swift
HopcastSDK.release()    // tears everything down; rebuild with the Builder to use again
```

---

## 4. API quick reference

| Area | API |
|---|---|
| Identity | `provision(sdkKey:userId:completion:)`, `isProvisioned`, `clearIdentity()`, `deviceUuid` |
| Setup | `builder(deviceId:cacheDirectory:)` → `setMode`, `setServiceId`, `setAutoAcceptConnections`, `setAutoAcceptTransfers`, `setOnlineConfig`, `build()` |
| Modes | `enableOnlineMode()`, `disableOnlineMode()`, `enableOfflineMode()`, `disableOfflineMode()`, `mode` |
| Online | `reportDownloadedFile(infraType:contentIds:)`, `reportRemovedFile(contentIds:)`, `declareNeed(contentId:ttlSeconds:)`, `cancelNeed(needId:)`, `handleFcmToken(_:)`, `handleFcmMessage(_:)` |
| Offline | `startSharing(listener:)`, `stopSharing()`, `inviteNeighbors(endpointIds:)`, `acceptInvitation(endpointId:)`, `rejectInvitation(endpointId:)`, `sendFiles(endpointIds:files:metadata:)`, `acceptTransfer(transferId:)`, `rejectTransfer(transferId:)`, `cancelTransfer(transferId:)` |
| Listeners | `setDeviceDiscoveryListener`, `setConnectionListener`, `setTransferListener`, `setOnlineEventListener`, `setTransferHandoffListener` (+ matching `remove…` calls) |
| Misc | `requiredPermissions`, `release()` |

---

## 5. Troubleshooting

- **Devices don't see each other** — both apps must use the same `serviceId`, the
  matching `NSBonjourServices` entries, and have Wi-Fi + Bluetooth enabled. The
  local-network permission prompt must have been accepted (Settings → Privacy → Local
  Network). Transfers require physical devices, not simulators.
- **Every call logs "not provisioned"** — `provision` has not succeeded on this device
  yet. Check `isProvisioned` and your SDK key.
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
