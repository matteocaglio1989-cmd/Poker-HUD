import SwiftUI

/// Phase 4 PR2: step-through controls for the visual replayer. Sits
/// directly below `PokerTableView` and binds to a `ReplayerEngine`.
///
/// Buttons:
///   • Rewind to start
///   • Previous action
///   • Play / pause (auto-advances at the chosen speed)
///   • Next action
///   • Fast-forward to end
///
/// The speed picker (1× / 2× / 4×) drives the auto-play timer interval.
/// A small action counter ("12 / 47") and the current step's descriptor
/// give the user a sense of where they are in the hand.
struct ReplayerControlsView: View {
    @ObservedObject var engine: ReplayerEngine
    @State private var isPlaying = false
    @State private var speed: PlaybackSpeed = .normal
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 8) {
            // Descriptor + counter row
            HStack {
                Text(engine.currentStep.descriptor)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(engine.currentIndex + 1) / \(engine.totalSteps)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            // Buttons row
            HStack(spacing: 16) {
                button(systemName: "backward.end.fill",
                       enabled: engine.canStepBack) {
                    stopPlayback()
                    withAnimation { engine.jumpToStart() }
                }

                button(systemName: "backward.fill",
                       enabled: engine.canStepBack) {
                    stopPlayback()
                    withAnimation { engine.stepBack() }
                }

                button(systemName: isPlaying ? "pause.fill" : "play.fill",
                       enabled: engine.canStepForward || isPlaying,
                       prominent: true) {
                    togglePlayback()
                }

                button(systemName: "forward.fill",
                       enabled: engine.canStepForward) {
                    stopPlayback()
                    withAnimation { engine.stepForward() }
                }

                button(systemName: "forward.end.fill",
                       enabled: engine.canStepForward) {
                    stopPlayback()
                    withAnimation { engine.jumpToEnd() }
                }

                Spacer()

                Picker("Speed", selection: $speed) {
                    ForEach(PlaybackSpeed.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: speed) { _, _ in
                    if isPlaying {
                        // Restart the timer at the new interval.
                        startPlayback()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Button helper

    private func button(
        systemName: String,
        enabled: Bool,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 22 : 16, weight: .semibold))
                .frame(width: prominent ? 40 : 32, height: prominent ? 40 : 32)
                .background(
                    Circle()
                        .fill(prominent ? Color.accentColor : Color.secondary.opacity(0.15))
                )
                .foregroundColor(prominent ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        timer?.invalidate()
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: speed.interval, repeats: true) { _ in
            if engine.canStepForward {
                withAnimation {
                    engine.stepForward()
                }
            } else {
                stopPlayback()
            }
        }
    }

    private func stopPlayback() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }
}

// MARK: - Speed

enum PlaybackSpeed: String, CaseIterable, Identifiable, Hashable {
    case normal = "1x"
    case fast   = "2x"
    case turbo  = "4x"

    var id: String { rawValue }
    var label: String { rawValue }

    /// Seconds between auto-advance ticks.
    var interval: TimeInterval {
        switch self {
        case .normal: return 1.2
        case .fast:   return 0.6
        case .turbo:  return 0.3
        }
    }
}
