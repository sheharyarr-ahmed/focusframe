import ActivityKit
import SwiftUI
import WidgetKit

struct FocusSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusSessionAttributes.self) { context in
            lockScreenView(for: context)
                .activityBackgroundTint(.focusBackground)
                .activitySystemActionForegroundColor(.focusAccent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundStyle(.focusAccent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .foregroundStyle(.focusAccent)
                        .frame(maxWidth: 80)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.goalText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.callout)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.distractionCount > 0 {
                        Label("\(context.state.distractionCount) distractions", systemImage: "exclamationmark.triangle")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.focusAccent)
                    }
                }
            } compactLeading: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.focusAccent)
            } compactTrailing: {
                Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .foregroundStyle(.focusAccent)
                    .frame(maxWidth: 50)
            } minimal: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.focusAccent)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(for context: ActivityViewContext<FocusSessionAttributes>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("FocusFrame", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.focusAccent)
                Spacer()
                Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.focusAccent)
            }

            Text(context.attributes.goalText)
                .font(.title3)
                .lineLimit(2)
                .foregroundStyle(.focusAccent)

            HStack(alignment: .center, spacing: Spacing.md) {
                if let planned = context.attributes.plannedDurationMinutes {
                    progressBar(elapsedSeconds: context.state.elapsedSeconds, plannedMinutes: planned)
                } else {
                    Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                }
                Spacer()
                if context.state.distractionCount > 0 {
                    Label("\(context.state.distractionCount)", systemImage: "exclamationmark.triangle")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.focusAccent)
                }
            }
        }
        .padding(Spacing.md)
    }

    @ViewBuilder
    private func progressBar(elapsedSeconds: Int, plannedMinutes: Int) -> some View {
        let plannedSeconds = max(plannedMinutes * 60, 1)
        let progress = min(Double(elapsedSeconds) / Double(plannedSeconds), 1.0)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.1))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.focusAccent)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 8)
    }
}
