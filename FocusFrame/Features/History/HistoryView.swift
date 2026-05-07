import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \Session.endedAt, order: .reverse)
    private var sessions: [Session]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.focusBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("History")
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(session: session)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "No sessions yet",
                systemImage: "clock",
                description: Text("Your finished sessions will appear here.")
            )
            .foregroundStyle(.white.opacity(0.7))
        } else {
            List(sessions) { session in
                NavigationLink(value: session) {
                    SessionRow(session: session)
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(session.goalText)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(2)

            HStack(spacing: Spacing.sm) {
                Label("\(session.durationMinutes) min", systemImage: "timer")
                    .foregroundStyle(.focusAccent)
                Spacer()
                Text(session.endedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.caption)
        }
        .padding(.vertical, Spacing.xs)
    }
}
