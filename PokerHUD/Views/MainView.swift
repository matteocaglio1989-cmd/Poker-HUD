import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SidebarItem = .dashboard

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedTab) {
                ForEach(SidebarItem.allCases) { item in
                    NavigationLink(value: item) {
                        Label(item.title, systemImage: item.icon)
                    }
                }
            }
            .navigationTitle("Poker HUD")
            .frame(minWidth: 200)
            // Pin the trial banner (when on a free trial) to the bottom of
            // the sidebar column instead of overlaying the whole window —
            // safeAreaInset reserves vertical space inside the List so the
            // banner never covers a nav item.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if case .trial(let remaining) = appState.subscriptionManager.entitlement {
                    TrialBannerView(remainingSeconds: remaining)
                }
            }
        } detail: {
            // Main content
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView()
                case .reports:
                    ReportsView()
                case .sessions:
                    SessionsView()
                case .hud:
                    TableSetupView()
                case .replayer:
                    ReplayerPlaceholderView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case reports
    case sessions
    case hud
    case replayer
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .reports: return "Reports"
        case .sessions: return "Sessions"
        case .hud: return "HUD"
        case .replayer: return "Hand Replayer"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "chart.line.uptrend.xyaxis"
        case .reports: return "doc.text.magnifyingglass"
        case .sessions: return "calendar"
        case .hud: return "rectangle.on.rectangle"
        case .replayer: return "play.circle.fill"
        case .settings: return "gear"
        }
    }
}

// Placeholder views
struct ReplayerPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Hand Replayer")
                .font(.title)
            Text("Coming in Phase 4")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// OpponentListView moved to Phase 3
