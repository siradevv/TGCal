import SwiftUI

enum RootTab: Hashable {
    case overview
    case roster
    case earnings
    case settings
}

struct RootTabView: View {
    @EnvironmentObject private var store: TGCalStore
    @State private var selectedTab: RootTab = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView {
                selectedTab = .roster
            }
            .environmentObject(store)
            .tabItem {
                Label("Overview", systemImage: "house")
            }
            .tag(RootTab.overview)

            ContentView()
                .environmentObject(store)
                .tabItem {
                    Label("Roster", systemImage: "airplane")
                }
                .tag(RootTab.roster)

            EarningsView()
                .environmentObject(store)
                .tabItem {
                    Label("Earnings", systemImage: "chart.bar")
                }
                .tag(RootTab.earnings)

            SettingsView()
                .environmentObject(store)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
        }
    }
}
