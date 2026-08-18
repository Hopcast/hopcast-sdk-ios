import SwiftUI

struct RootView: View {
    @EnvironmentObject private var controller: HopcastController

    var body: some View {
        if controller.isProvisioned {
            TabView {
                DashboardView()
                    .tabItem { Label("Tableau de bord", systemImage: "antenna.radiowaves.left.and.right") }
                JournalView()
                    .tabItem { Label("Journal", systemImage: "list.bullet.rectangle") }
                SettingsView()
                    .tabItem { Label("Réglages", systemImage: "gearshape") }
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
                    TextField("Clé SDK (pk_live_…)", text: $sdkKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    TextField("Identifiant utilisateur", text: $userId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Enrôlement")
                } footer: {
                    Text("La clé SDK est fournie par Hopcast. L'enrôlement n'a lieu qu'une fois : "
                         + "l'identité device (device_id + JWT) est ensuite conservée dans le Keychain.")
                }

                Section {
                    Button("Enrôler ce device") {
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
