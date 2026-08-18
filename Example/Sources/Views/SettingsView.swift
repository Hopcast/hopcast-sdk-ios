import SwiftUI
import HopcastKit

/// Read-mostly settings screen: identity, backend endpoints, cache state, app info.
/// The only mutable setting is the MQTT broker override — persisted in UserDefaults
/// and applied at the next launch (the SDK is built once per process).
struct SettingsView: View {
    @EnvironmentObject private var controller: HopcastController
    @State private var brokerField = ""
    @FocusState private var brokerFieldFocused: Bool

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var cacheBytes: Int64 {
        controller.contents.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        NavigationStack {
            List {
                identitySection
                backendSection
                brokerSection
                appSection
            }
            .navigationTitle("Réglages")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { brokerFieldFocused = false }
                }
            }
            .onAppear { brokerField = controller.brokerOverride }
        }
    }

    private var identitySection: some View {
        Section("Identité") {
            LabeledContent("Device ID") {
                Text(controller.deviceId)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("Utilisateur", value: controller.userId)
            LabeledContent("Clé SDK") {
                Text(controller.sdkKey.prefix(16) + "…")
                    .font(.system(.caption, design: .monospaced))
            }
            Button(role: .destructive) {
                controller.resetIdentity()
            } label: {
                Label("Réinitialiser l'identité", systemImage: "person.crop.circle.badge.xmark")
            }
        }
    }

    private var backendSection: some View {
        Section {
            LabeledContent("API REST") {
                Text("https://api.hopcast.io")
                    .font(.system(.caption, design: .monospaced))
            }
            LabeledContent("Broker MQTT") {
                Text(controller.effectiveBrokerUrl)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("Session MQTT") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(controller.cloudConnected ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(controller.cloudConnected ? "connectée" : "déconnectée")
                }
            }
        } header: {
            Text("Backend")
        } footer: {
            Text("L'API REST (enrôlement, refresh JWT, reporting /v1/exchanges) est fixée par le SDK.")
        }
    }

    private var brokerSection: some View {
        Section {
            TextField("wss://mqtt.hopcast.io/mqtt (défaut si vide)", text: $brokerField)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($brokerFieldFocused)
                .font(.system(.caption, design: .monospaced))
            Button("Appliquer") {
                controller.setBrokerOverride(brokerField)
                brokerFieldFocused = false
            }
            .disabled(brokerField.trimmingCharacters(in: .whitespaces) == controller.brokerOverride)
        } header: {
            Text("Broker override")
        } footer: {
            Text("Vide = broker de production du SDK. Ex. local : ws://192.168.68.151:9001. "
                 + "Prend effet au prochain lancement de l'app.")
        }
    }

    private var appSection: some View {
        Section("Application") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Mode SDK", value: "\(HopcastSDK.mode)")
            LabeledContent("Contenus en cache") {
                Text("\(controller.contents.count) — \(cacheBytes) o")
            }
            LabeledContent("Répertoire cache") {
                Text(DemoConfig.cacheDirectory.path)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
    }
}
