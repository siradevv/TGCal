import SwiftUI

enum Tab: Hashable {
    case overview
    case roster
    case logbook
    case settings
}

struct RootTabView: View {
    @EnvironmentObject private var store: TGCalStore
    @State private var selectedTab: Tab = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView(selectedTab: $selectedTab)
                .environmentObject(store)
                .tabItem {
                    Label("Overview", systemImage: "house")
                }
                .tag(Tab.overview)

            ContentView()
                .environmentObject(store)
                .tabItem {
                    Label("Flights", systemImage: "airplane")
                }
                .tag(Tab.roster)

            LogbookView()
                .environmentObject(store)
                .tabItem {
                    Label("Logbook", systemImage: "chart.bar.xaxis")
                }
                .tag(Tab.logbook)

            SettingsView()
                .environmentObject(store)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
    }
}
