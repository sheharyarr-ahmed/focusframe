import Charts
import SwiftUI

private struct DayBucket: Identifiable {
    let day: Date
    let totalMinutes: Int
    var id: Date { day }
}

struct WeeklyTrendChart: View {
    let sessions: [Session]

    private var buckets: [DayBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.endedAt)
        }

        return (-6...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            let total = (grouped[day] ?? []).reduce(0) { $0 + $1.durationMinutes }
            return DayBucket(day: day, totalMinutes: total)
        }
    }

    private var isEmptyWeek: Bool {
        buckets.allSatisfy { $0.totalMinutes == 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Last 7 days")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            if isEmptyWeek {
                Text("No sessions yet this week")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Day", bucket.day, unit: .day),
                        y: .value("Minutes", bucket.totalMinutes)
                    )
                    .foregroundStyle(Color.focusAccent)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 140)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }
}
