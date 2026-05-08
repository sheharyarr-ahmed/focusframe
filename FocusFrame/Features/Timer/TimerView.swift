import SwiftUI

struct TimerView: View {
    @Environment(AppState.self) private var state
    @State private var goalDraft: String = ""
    @State private var isShowingSettings: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.focusBackground.ignoresSafeArea()
                content
                    .padding(Spacing.lg)
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens app settings")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let active = state.sessionManager.currentSession {
            activeSessionView(active)
        } else {
            idleView
        }
    }

    private var idleView: some View {
        VStack(spacing: Spacing.xl) {
            TextField(
                "What are you focusing on?",
                text: $goalDraft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .lineLimit(3, reservesSpace: true)
            .padding(Spacing.md)
            .background(.white.opacity(0.05), in: .rect(cornerRadius: 12))
            .foregroundStyle(.white)

            Text("00:00")
                .font(.system(size: 80, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityHidden(true)

            Button("Start Session", systemImage: "play.fill") {
                state.sessionManager.startSession(goalText: goalDraft)
                goalDraft = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.focusAccent)
            .foregroundStyle(.black)
            .disabled(goalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint("Begins a new focus session")

            Spacer()
        }
    }

    private func activeSessionView(_ active: ActiveSession) -> some View {
        VStack(spacing: Spacing.xl) {
            Text(active.goalText)
                .font(.title3)
                .foregroundStyle(.focusAccent)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            TimelineView(.periodic(from: active.startedAt, by: 1)) { context in
                let elapsed = max(0, Int(context.date.timeIntervalSince(active.startedAt)))
                Text(timerInterval: active.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 80, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue("\(elapsed) seconds")
            }

            Button("End Session", systemImage: "stop.fill", role: .destructive) {
                state.sessionManager.endSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Ends and saves the current session")

            Spacer()
        }
    }
}
