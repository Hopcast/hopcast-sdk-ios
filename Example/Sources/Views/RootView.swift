import SwiftUI

struct RootView: View {
    @EnvironmentObject private var controller: HopcastController

    var body: some View {
        if controller.isProvisioned {
            TabView {
                DashboardView()
                    .tabItem { Label("Dashboard", systemImage: "antenna.radiowaves.left.and.right") }
                JournalView()
                    .tabItem { Label("Journal", systemImage: "list.bullet.rectangle") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        } else {
            ProvisionView()
        }
    }
}

/// First-launch screen: enroll the device with the tenant SDK key.
struct ProvisionView: View {
    @EnvironmentObject private var controller: HopcastController
    @State private var sdkKey = ""
    @State private var userId = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("SDK key (pk_live_…)", text: $sdkKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    TextField("User identifier", text: $userId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Enrollment")
                } footer: {
                    Text("Get your SDK key (pk_live_…) from your Hopcast account console. Enrollment "
                         + "happens once: the device identity is then kept in the Keychain.")
                }

                Section {
                    Button("Enroll this device") {
                        controller.sdkKey = sdkKey
                        controller.userId = userId
                        controller.provision()
                    }
                    .disabled(sdkKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let last = controller.journal.first, case .error = last.kind {
                    Section {
                        Text(last.message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Hopcast Demo")
            .onAppear {
                sdkKey = controller.sdkKey
                userId = controller.userId
            }
        }
    }
}
