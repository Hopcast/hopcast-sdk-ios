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
            .navigationTitle("Settings")
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
        Section("Identity") {
            LabeledContent("Device ID") {
                Text(controller.deviceId)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("User", value: controller.userId)
            LabeledContent("SDK key") {
                Text(controller.sdkKey.prefix(16) + "…")
                    .font(.system(.caption, design: .monospaced))
            }
            Button(role: .destructive) {
                controller.resetIdentity()
            } label: {
                Label("Reset identity", systemImage: "person.crop.circle.badge.xmark")
            }
        }
    }

    private var backendSection: some View {
        Section {
            LabeledContent("REST API") {
                Text("https://api.hopcast.io")
                    .font(.system(.caption, design: .monospaced))
            }
            LabeledContent("Cloud endpoint") {
                Text(controller.effectiveBrokerUrl)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("Cloud session") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(controller.cloudConnected ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(controller.cloudConnected ? "connected" : "disconnected")
                }
            }
        } header: {
            Text("Backend")
        } footer: {
            Text("The REST API (enrollment, token refresh, exchange reporting) is fixed by the SDK.")
        }
    }

    private var brokerSection: some View {
        Section {
            TextField("production default if empty", text: $brokerField)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($brokerFieldFocused)
                .font(.system(.caption, design: .monospaced))
            Button("Apply") {
                controller.setBrokerOverride(brokerField)
                brokerFieldFocused = false
            }
            .disabled(brokerField.trimmingCharacters(in: .whitespaces) == controller.brokerOverride)
        } header: {
            Text("Endpoint override (advanced)")
        } footer: {
            Text("Empty = the SDK's production endpoint. Takes effect at the next app launch. "
                 + "Leave unchanged unless instructed by Hopcast support.")
        }
    }

    private var appSection: some View {
        Section("Application") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("SDK mode", value: "\(HopcastSDK.mode)")
            LabeledContent("Cached contents") {
                Text("\(controller.contents.count) — \(cacheBytes) B")
            }
            LabeledContent("Cache directory") {
                Text(DemoConfig.cacheDirectory.path)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
    }
}
