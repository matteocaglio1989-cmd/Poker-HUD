import SwiftUI
import Charts

/// Phase 3 PR3: detail view for one historical session. Shown as a sheet
/// from `SessionsView`. Renders:
///
///   • A header with the session's headline numbers
///   • A cumulative profit/loss line chart (Swift Charts, macOS 14+)
///   • A scrollable list of every hand in the session
///
/// The session passed in must already have its `handPoints` populated by
/// `SessionDetector.detail(for:heroPlayerName:)` — the bulk
/// `allSessions(...)` query doesn't include them because the chart data
/// is only needed when you actually open one session.
struct SessionDetailView: View {
    let session: Session
    let heroPlayerName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statsCards
                    profitChart
                    handsList
                }
                .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if session.isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Text(session.tableName)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text("\(heroPlayerName) · \(session.stakes)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(session.startTime, format: .dateTime.weekday(.wide).day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Stat cards

    private var statsCards: some View {
        HStack(spacing: 12) {
            statCard(label: "Net", value: String(format: "%+.2f", session.netResult),
                     valueColor: session.netResult >= 0 ? .green : .red)
            statCard(label: "BB/100", value: String(format: "%+.1f", session.bb100),
                     valueColor: session.bb100 >= 0 ? .green : .red)
            statCard(label: "Hands", value: "\(session.handsPlayed)", valueColor: .primary)
            statCard(label: "Duration", value: session.durationFormatted, valueColor: .primary)
            statCard(label: "Hands/hr", value: "\(session.handsPerHour)", valueColor: .primary)
        }
    }

    private func statCard(label: String, value: String, valueColor: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Chart

    @ViewBuilder
    private var profitChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cumulative Profit")
                .font(.headline)
            if session.handPoints.isEmpty {
                Text("No hand data available for this session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.05))
                    )
            } else {
                Chart(session.handPoints) { point in
                    LineMark(
                        x: .value("Hand", point.handIndex),
                        y: .value("Cumulative", point.cumulativeNet)
                    )
                    .foregroundStyle(session.netResult >= 0 ? Color.green : Color.red)
                    .interpolationMethod(.linear)
                    AreaMark(
                        x: .value("Hand", point.handIndex),
                        y: .value("Cumulative", point.cumulativeNet)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                (session.netResult >= 0 ? Color.green : Color.red).opacity(0.3),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.1f", v))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    // MARK: - Hand list

    @ViewBuilder
    private var handsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hands (\(session.handPoints.count))")
                .font(.headline)
            if session.handPoints.isEmpty {
                Text("Per-hand details unavailable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(session.handPoints) { point in
                        HStack {
                            Text("#\(point.handIndex)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .leading)
                            Text(point.playedAt, format: .dateTime.hour().minute().second())
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            Text(String(format: "%+.2f", point.netResult))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(point.netResult >= 0 ? .green : .red)
                                .frame(width: 80, alignment: .trailing)
                            Text(String(format: "%+.2f", point.cumulativeNet))
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(point.cumulativeNet >= 0 ? .green : .red)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        Divider()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.05))
                )
            }
        }
    }
}
