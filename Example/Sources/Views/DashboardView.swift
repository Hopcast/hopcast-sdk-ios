import SwiftUI
import HopcastKit

struct DashboardView: View {
    @EnvironmentObject private var controller: HopcastController
    @State private var neededContentId = ""
    @State private var needTtl = 300
    @FocusState private var needFieldFocused: Bool

    private static let sampleSizes: [(label: String, bytes: Int)] = [
        ("50 KB", 50_000),
        ("1 MB", 1_000_000),
        ("10 MB", 10_000_000),
        ("50 MB", 50_000_000),
    ]

    var body: some View {
        NavigationStack {
            List {
                statusSection
                neighborsSection
                contentsSection
                needsSection
            }
            .navigationTitle("Hopcast Demo")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // numberPad has no return key — offer an explicit dismiss.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { needFieldFocused = false }
                }
            }
        }
    }

    // MARK: - Cloud status

    private var statusSection: some View {
        Section("Cloud") {
            LabeledContent("Device") {
                Text(controller.deviceId)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Toggle("Online mode", isOn: Binding(
                get: { controller.onlineEnabled },
                set: { controller.setOnline($0) }
            ))
            LabeledContent("Session") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(controller.cloudConnected ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(controller.cloudConnected ? "connected" : "disconnected")
                }
            }
        }
    }

    // MARK: - Neighbors

    private var neighborsSection: some View {
        Section("Nearby devices") {
            if controller.neighbors.isEmpty {
                Text("No device detected")
                    .foregroundStyle(.secondary)
            }
            ForEach(controller.neighbors, id: \.endpointId) { neighbor in
                HStack {
                    VStack(alignment: .leading) {
                        Text(neighbor.displayName)
                            .font(.system(.caption, design: .monospaced))
                        Text(controller.connectedNeighbors.contains(neighbor.endpointId)
                             ? "connected" : "discovered")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !controller.connectedNeighbors.contains(neighbor.endpointId) {
                        Button("Connect") { controller.connect(to: neighbor) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - Contents (has)

    private var contentsSection: some View {
        Section {
            ForEach(controller.contents) { content in
                HStack {
                    VStack(alignment: .leading) {
                        Text(content.contentId)
                            .font(.system(.caption, design: .monospaced))
                        Text("\(content.bytes) bytes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if controller.expectedContents.contains(content.contentId) {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundStyle(.blue)
                    }
                }
                .contextMenu {
                    ForEach(controller.neighbors.filter {
                        controller.connectedNeighbors.contains($0.endpointId)
                    }, id: \.endpointId) { neighbor in
                        Button("Send to \(neighbor.displayName)") {
                            controller.send(content, to: neighbor)
                        }
                    }
                    Button(role: .destructive) {
                        controller.deleteContent(content)
                    } label: {
                        Label("Delete (has/remove)", systemImage: "trash")
                    }
                }
            }
            Menu {
                ForEach(Self.sampleSizes, id: \.bytes) { size in
                    Button(size.label) { controller.createSampleContent(size: size.bytes) }
                }
            } label: {
                Label("Create a demo content (has/new)", systemImage: "plus")
            }
        } header: {
            Text("Local contents")
        } footer: {
            Text("The file name is the content_id. Long-press a content for manual send or delete.")
        }
    }

    // MARK: - Needs

    private var needsSection: some View {
        Section {
            ForEach(controller.needs) { need in
                HStack {
                    VStack(alignment: .leading) {
                        Text(need.contentId)
                            .font(.system(.caption, design: .monospaced))
                        Text("need \(need.needId.prefix(8))… · TTL \(need.ttlSeconds)s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { controller.cancelNeed(need) }
                        .buttonStyle(.bordered)
                }
            }
            HStack {
                // The "demo-" prefix is fixed; only the 5 digits are typed.
                Text("demo-")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("12345", text: $neededContentId)
                    .keyboardType(.numberPad)
                    .focused($needFieldFocused)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: neededContentId) { value in
                        let digits = value.filter(\.isNumber)
                        if digits != value { neededContentId = digits }
                    }
                Button("Request") {
                    let digits = neededContentId.trimmingCharacters(in: .whitespaces)
                    guard !digits.isEmpty else { return }
                    controller.declareNeed(contentId: "demo-" + digits, ttlSeconds: needTtl)
                    neededContentId = ""
                    needFieldFocused = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(neededContentId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Needs")
        } footer: {
            Text("Files a need: Hopcast will automatically deliver this content from a nearby "
                 + "device that has it.")
        }
    }
}
