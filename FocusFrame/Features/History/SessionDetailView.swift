import SwiftData
import SwiftUI

struct SessionDetailView: View {
    let session: Session

    @Environment(AppState.self) private var state
    @Query private var insights: [Insight]

    init(session: Session) {
        self.session = session
        let sid = session.id
        _insights = Query(
            filter: #Predicate<Insight> { $0.sessionID == sid },
            sort: \Insight.generatedAt
        )
    }

    private var insight: Insight? { insights.first }

    var body: some View {
        ZStack {
            Color.focusBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    goalSection
                    metadataSection
                    insightSection
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Goal")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Text(session.goalText)
                .font(.title2)
                .foregroundStyle(.white)
        }
    }

    private var metadataSection: some View {
        HStack(spacing: Spacing.md) {
            Label("\(session.durationMinutes) min", systemImage: "timer")
            Label("\(session.distractionCount)", systemImage: "exclamationmark.triangle")
            Spacer()
            Text(session.endedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                .foregroundStyle(.white.opacity(0.6))
        }
        .font(.caption)
        .foregroundStyle(.focusAccent)
    }

    @ViewBuilder
    private var insightSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Insight")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            switch insight?.statusEnum {
            case .succeeded:
                Text(insight?.text ?? "")
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineSpacing(4)
            case .pending:
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("Generating insight…")
                        .foregroundStyle(.white.opacity(0.7))
                }
            case .failed, .none:
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Insight generation failed.")
                        .foregroundStyle(.white)
                    Button("Retry") {
                        state.sessionManager.retryInsight(for: session)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.focusAccent)
                    .foregroundStyle(.black)
                }
            }
        }
        .padding(Spacing.md)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}
