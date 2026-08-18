import Foundation
import SwiftUI
import UIKit
import HopcastKit

/// A journal line shown in the app — everything the SDK reports lands here.
struct LogEntry: Identifiable {
    enum Kind { case cloud, transfer, discovery, action, error }
    let id = UUID()
    let date = Date()
    let kind: Kind
    let message: String
}

/// A file present in the demo cache. The file name is the `content_id`.
struct LocalContent: Identifiable, Equatable {
    var id: String { contentId }
    let contentId: String
    let bytes: Int64
}

/// A need filed from this device.
struct FiledNeed: Identifiable, Equatable {
    var id: String { needId }
    let needId: String
    let contentId: String
    let ttlSeconds: Int
    let filedAt = Date()
}

/// Single owner of the SDK for the demo app: builds it, provisions it, registers every
/// listener and republishes the state as `@Published` properties for SwiftUI.
///
/// All mutations happen on the main queue — the SDK already delivers its listener
/// callbacks there.
final class HopcastController: ObservableObject {

    @Published var isProvisioned = HopcastSDK.isProvisioned
    @Published var deviceId = HopcastSDK.deviceUuid
    @Published var cloudConnected = false
    @Published var onlineEnabled = false
    @Published var neighbors: [Neighbor] = []
    @Published var connectedNeighbors: Set<String> = []
    @Published var contents: [LocalContent] = []
    @Published var needs: [FiledNeed] = []
    @Published var journal: [LogEntry] = []
    /// contentIds the backend told us to expect (onFilesToBeDownloaded).
    @Published var expectedContents: Set<String> = []

    @AppStorage("sdkKey") var sdkKey: String = DemoConfig.defaultSdkKey
    @AppStorage("userId") var userId: String = DemoConfig.defaultUserId
    /// MQTT broker override, editable from the settings tab. Empty = SDK production
    /// default. Applied at the next launch (the SDK is built once per process).
    @AppStorage("brokerOverride") var brokerOverride: String = DemoConfig.brokerOverride ?? ""

    /// The broker URL the SDK was actually built with in this process.
    var effectiveBrokerUrl: String {
        let override = brokerOverride.trimmingCharacters(in: .whitespaces)
        return override.isEmpty ? OnlineConfig.defaultBrokerUrl.absoluteString : override
    }

    func setBrokerOverride(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, URL(string: trimmed)?.scheme == nil {
            log(.error, "URL broker invalide : \(trimmed)")
            return
        }
        brokerOverride = trimmed
        objectWillChange.send()
        log(.action, "Broker override → \(trimmed.isEmpty ? "défaut prod" : trimmed) — relance l'app pour appliquer")
    }

    private var built = false
    private let listenerTag = "demo"

    init() {
        refreshContents()
        if isProvisioned {
            bootstrap()
        }
    }

    // ------------------------------------------------------------------------
    // Provisioning & build
    // ------------------------------------------------------------------------

    func provision() {
        let key = sdkKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            log(.error, "Clé SDK manquante — renseigne pk_live_…")
            return
        }
        log(.action, "Enrôlement du device…")
        HopcastSDK.provision(sdkKey: key, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.isProvisioned = true
                    self.deviceId = HopcastSDK.deviceUuid
                    self.log(.action, "Device enrôlé : \(self.deviceId)")
                    self.bootstrap()
                case .failure(let error):
                    self.log(.error, "Échec de l'enrôlement : \(error.localizedDescription)")
                }
            }
        }
    }

    /// Drops the identity (tenant key rotation / test reset). The app must be relaunched
    /// to rebuild the SDK from scratch afterwards.
    func resetIdentity() {
        HopcastSDK.release()
        HopcastSDK.clearIdentity()
        isProvisioned = false
        onlineEnabled = false
        cloudConnected = false
        built = false
        log(.action, "Identité effacée — relance l'app pour ré-enrôler")
    }

    /// Builds the SDK singleton. Called once, after provisioning (the advertised
    /// Multipeer name is the backend device_id, so the identity must exist first).
    private func bootstrap() {
        guard !built else { return }
        built = true

        var config = OnlineConfig()
        let override = brokerOverride.trimmingCharacters(in: .whitespaces)
        if !override.isEmpty, let url = URL(string: override) {
            config = OnlineConfig(brokerUrl: url)
        }

        HopcastSDK
            .builder(deviceId: UIDevice.current.name, cacheDirectory: DemoConfig.cacheDirectory)
            .setMode(.hybrid)
            .setServiceId("hopcast")
            .setAutoAcceptConnections(true)   // required for cloud-driven links
            .setAutoAcceptTransfers(true)     // demo: no manual accept dialog
            .setOnlineConfig(config)
            .build()

        HopcastSDK.setDeviceDiscoveryListener(self)
        HopcastSDK.setConnectionListener(self, tag: listenerTag)
        HopcastSDK.setTransferListener(self, tag: listenerTag)
        HopcastSDK.setOnlineEventListener(self, tag: listenerTag)
        HopcastSDK.setTransferHandoffListener(self, tag: listenerTag)

        deviceId = HopcastSDK.deviceUuid
        log(.action, "SDK construit (mode hybrid, device \(deviceId))")
    }

    // ------------------------------------------------------------------------
    // Online mode
    // ------------------------------------------------------------------------

    func setOnline(_ enabled: Bool) {
        onlineEnabled = enabled
        if enabled {
            HopcastSDK.enableOnlineMode()
            log(.action, "Mode online activé — connexion MQTT en cours")
        } else {
            HopcastSDK.disableOnlineMode()
            cloudConnected = false
            log(.action, "Mode online désactivé")
        }
    }

    // ------------------------------------------------------------------------
    // Contents (has)
    // ------------------------------------------------------------------------

    func refreshContents() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: DemoConfig.cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        contents = urls
            .filter { !$0.hasDirectoryPath }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return LocalContent(contentId: url.lastPathComponent, bytes: Int64(size))
            }
            .sorted { $0.contentId < $1.contentId }
    }

    /// Creates a random file of `size` bytes in the cache and declares it to the backend
    /// (`has/new`, source wifi) so it becomes matchable inventory. The content_id is
    /// `demo-` + 5 digits, matching the pre-filled prefix of the need field.
    func createSampleContent(size: Int = 50_000) {
        let contentId = String(format: "demo-%05d", Int.random(in: 0...99_999))
        let url = DemoConfig.cacheDirectory.appendingPathComponent(contentId)
        // One random 64 KB chunk repeated to size — fast even for tens of MB.
        let chunk = Data((0..<min(size, 65_536)).map { _ in UInt8.random(in: 0...255) })
        do {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            var written = 0
            while written < size {
                let slice = chunk.prefix(size - written)
                try handle.write(contentsOf: slice)
                written += slice.count
            }
        } catch {
            log(.error, "Écriture du contenu impossible : \(error.localizedDescription)")
            return
        }
        HopcastSDK.reportDownloadedFile(infraType: .wifi, contentIds: [contentId])
        log(.action, "Contenu \(contentId) créé (\(size) o) et déclaré (has/new)")
        refreshContents()
    }

    func deleteContent(_ content: LocalContent) {
        try? FileManager.default.removeItem(
            at: DemoConfig.cacheDirectory.appendingPathComponent(content.contentId)
        )
        HopcastSDK.reportRemovedFile(contentIds: [content.contentId])
        log(.action, "Contenu \(content.contentId) supprimé (has/remove)")
        refreshContents()
    }

    /// Manual D2D send (offline flow) to a connected neighbor — handy to sanity-check
    /// the radio path between two demo devices.
    func send(_ content: LocalContent, to neighbor: Neighbor) {
        let url = DemoConfig.cacheDirectory.appendingPathComponent(content.contentId)
        if let transferId = HopcastSDK.sendFiles(endpointIds: [neighbor.endpointId], files: [url]) {
            log(.transfer, "Envoi manuel de \(content.contentId) vers \(neighbor.displayName) (\(transferId))")
        } else {
            log(.error, "Envoi impossible — voisin non connecté ?")
        }
    }

    // ------------------------------------------------------------------------
    // Needs
    // ------------------------------------------------------------------------

    func declareNeed(contentId: String, ttlSeconds: Int) {
        guard let needId = HopcastSDK.declareNeed(contentId: contentId, ttlSeconds: ttlSeconds) else {
            log(.error, "declareNeed refusé (SDK non provisionné ou online absent)")
            return
        }
        needs.append(FiledNeed(needId: needId, contentId: contentId, ttlSeconds: ttlSeconds))
        log(.action, "Besoin déclaré pour \(contentId) (need \(needId.prefix(8))…, TTL \(ttlSeconds)s)")
    }

    func cancelNeed(_ need: FiledNeed) {
        HopcastSDK.cancelNeed(needId: need.needId)
        needs.removeAll { $0.needId == need.needId }
        log(.action, "Besoin \(need.needId.prefix(8))… annulé")
    }

    // ------------------------------------------------------------------------
    // Neighbors
    // ------------------------------------------------------------------------

    func connect(to neighbor: Neighbor) {
        HopcastSDK.inviteNeighbors(endpointIds: [neighbor.endpointId])
        log(.discovery, "Invitation envoyée à \(neighbor.displayName)")
    }

    // ------------------------------------------------------------------------
    // Journal
    // ------------------------------------------------------------------------

    func log(_ kind: LogEntry.Kind, _ message: String) {
        let entry = LogEntry(kind: kind, message: message)
        if Thread.isMainThread {
            journal.insert(entry, at: 0)
        } else {
            DispatchQueue.main.async { self.journal.insert(entry, at: 0) }
        }
    }
}

// ----------------------------------------------------------------------------
// SDK listeners — all delivered on the main queue by the SDK
// ----------------------------------------------------------------------------

extension HopcastController: DeviceDiscoveryListener {
    func onNeighborsChanged(_ neighbors: [Neighbor]) {
        self.neighbors = neighbors
        log(.discovery, "Voisinage : \(neighbors.isEmpty ? "aucun appareil" : neighbors.map(\.displayName).joined(separator: ", "))")
    }
}

extension HopcastController: ConnectionListener {
    func onConnectionStateChanged(state: ConnectionState, neighbor: Neighbor) {
        switch state {
        case .established: connectedNeighbors.insert(neighbor.endpointId)
        case .rejected, .disconnected: connectedNeighbors.remove(neighbor.endpointId)
        default: break
        }
        log(.discovery, "\(neighbor.displayName) → \(state)")
    }
}

extension HopcastController: TransferListener {
    func onTransferStateChanged(transferId: String, isReceiver: Bool, state: TransferState, peer: Neighbor) {
        log(.transfer, "Transfert \(transferId.prefix(8))… (\(isReceiver ? "réception" : "envoi")) : \(state)")
    }

    func onTransferEvent(_ event: TransferEvent) {
        switch event {
        case .fileCompleted(_, let isReceiver, let file, _, _, _, _):
            log(.transfer, "Fichier \(file.name) \(isReceiver ? "reçu" : "envoyé") (\(file.size) o)")
            if isReceiver { refreshContents() }
        case .transferFailed(_, _, let reason, _):
            log(.error, "Transfert échoué : \(reason)")
        default:
            break
        }
    }
}

extension HopcastController: OnlineEventListener {
    func onCloudReady(deviceUuid: String) {
        cloudConnected = true
        log(.cloud, "Session MQTT établie (device \(deviceUuid))")
    }

    func onCloudDisconnected() {
        cloudConnected = false
        log(.cloud, "Session MQTT perdue — reconnexion automatique")
    }

    func onCloudError(reason: String) {
        log(.error, "Erreur cloud : \(reason)")
    }

    func onFilesToBeDownloaded(fileIds: [String]) {
        fileIds.forEach { expectedContents.insert($0) }
        log(.cloud, "Instruction reçue : contenu(s) à obtenir \(fileIds.joined(separator: ", "))")
    }
}

extension HopcastController: TransferHandoffListener {
    func onTransferHandoff(_ handoff: TransferHandoff) {
        let bytes = handoff.bytesTotal.map { "\($0) o" } ?? "volume inconnu"
        log(.cloud, "Instruction \(handoff.instructionId.prefix(8))… terminée : \(handoff.status) (\(bytes))")
    }
}
