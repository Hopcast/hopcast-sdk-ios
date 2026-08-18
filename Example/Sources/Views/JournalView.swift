import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var controller: HopcastController

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        NavigationStack {
            List(controller.journal) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: entry.kind))
                        .foregroundStyle(color(for: entry.kind))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.caption)
                        Text(Self.time.string(from: entry.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Journal")
            .overlay {
                if controller.journal.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No events yet")
                            .font(.headline)
                        Text("Enable online mode to watch the cloud session live.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func icon(for kind: LogEntry.Kind) -> String {
        switch kind {
        case .cloud: return "icloud"
        case .transfer: return "arrow.left.arrow.right"
        case .discovery: return "dot.radiowaves.left.and.right"
        case .action: return "hand.tap"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func color(for kind: LogEntry.Kind) -> Color {
        switch kind {
        case .cloud: return .blue
        case .transfer: return .green
        case .discovery: return .orange
        case .action: return .primary
        case .error: return .red
        }
    }
}
