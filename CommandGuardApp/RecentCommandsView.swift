//  RecentCommandsView.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import SwiftUI

struct RecentCommandsView: View {
    let events: [RecentEvent]
    let timestampFormatter: (Date) -> String

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

                                Text(timestampFormatter(event.timestamp))
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
        timestampFormatter: { date in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }
    )
}
