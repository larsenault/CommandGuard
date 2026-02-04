import SwiftUI

struct RecentCommandsView: View {
    let events: [RecentEvent]
    let timestampFormatter: DateFormatter

    var body: some View {
        Form {
            if events.isEmpty {
                Section {
                    Text("No recent commands yet")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Recent Commands") {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.title)
                                    .font(.subheadline)
                                    .foregroundStyle(event.isSuccess ? .green : .red)

                                Spacer()

                                Text(timestampFormatter.string(from: event.timestamp))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(event.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let details = event.details {
                                Text(details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

#Preview {
    RecentCommandsView(
        events: [],
        timestampFormatter: {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            return formatter
        }()
    )
}
