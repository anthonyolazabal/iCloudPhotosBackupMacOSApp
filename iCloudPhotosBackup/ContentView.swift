import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @State private var selection: NavigationItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            DetailView(selection: selection)
        }
        .frame(minWidth: 900, minHeight: 600)
        .environment(appState)
    }
}

enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case backupJobs = "Backup Jobs"
    case scheduledJobs = "Scheduled Jobs"
    case verification = "Verification"
    case destinations = "Destinations"
    case history = "History"
    case settings = "Settings"
    case help = "Help"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge"
        case .backupJobs: return "arrow.clockwise.circle"
        case .scheduledJobs: return "calendar.badge.clock"
        case .verification: return "checkmark.shield"
        case .destinations: return "externaldrive.connected.to.line.below"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .help: return "book.fill"
        case .about: return "info.circle"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: NavigationItem?

    var body: some View {
        List(NavigationItem.allCases, id: \.self, selection: $selection) { item in
            NavigationLink(value: item) {
                Label(item.rawValue, systemImage: item.icon)
            }
        }
        .navigationTitle("iCloud Photos Backup")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
    }
}

struct DetailView: View {
    let selection: NavigationItem?

    var body: some View {
        Group {
            switch selection {
            case .dashboard:
                DashboardView()
            case .backupJobs:
                BackupJobsView()
            case .scheduledJobs:
                ScheduledJobsView()
            case .verification:
                VerificationView()
            case .destinations:
                DestinationsView()
            case .history:
                HistoryView()
            case .settings:
                SettingsView()
            case .help:
                DocumentationView()
            case .about:
                AboutView()
            case .none:
                DashboardView()
            }
        }
    }
}

#Preview {
    ContentView()
}
