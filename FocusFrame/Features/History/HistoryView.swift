import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var state
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
            VStack(spacing: Spacing.md) {
                WeeklyTrendChart(sessions: sessions)
                List(sessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            state.sessionManager.deleteSession(session)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
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
                if session.distractionCount > 0 {
                    Label("\(session.distractionCount)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.focusAccent)
                        .accessibilityLabel("\(session.distractionCount) distractions")
                }
                Spacer()
                Text(session.endedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.caption)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
