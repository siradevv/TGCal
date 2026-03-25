import SwiftUI

enum Tab: Hashable {
    case home
    case flights
    case swap
    case crew
    case settings
}

struct RootTabView: View {
    @EnvironmentObject private var store: TGCalStore
    @State private var selectedTab: Tab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarTabView(selectedTab: $selectedTab)
                .environmentObject(store)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(Tab.home)

            ContentView()
                .environmentObject(store)
                .tabItem {
                    Label("Flights", systemImage: "airplane")
                }
                .tag(Tab.flights)

            SwapBoardView()
                .environmentObject(store)
                .tabItem {
                    Label("Swap", systemImage: "arrow.triangle.swap")
                }
                .tag(Tab.swap)

            CrewHubView()
                .environmentObject(store)
                .tabItem {
                    Label("Crew", systemImage: "person.2")
                }
                .tag(Tab.crew)

            SettingsView()
                .environmentObject(store)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
    }
}
