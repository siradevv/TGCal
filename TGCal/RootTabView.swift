import SwiftUI

enum Tab: Hashable {
    case calendar
    case roster
    case swap
    case crew
    case more
}

struct RootTabView: View {
    @EnvironmentObject private var store: TGCalStore
    @State private var selectedTab: Tab = .calendar

    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarTabView(selectedTab: $selectedTab)
                .environmentObject(store)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(Tab.calendar)

            ContentView()
                .environmentObject(store)
                .tabItem {
                    Label("Roster", systemImage: "airplane")
                }
                .tag(Tab.roster)

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

            MoreTabView()
                .environmentObject(store)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .tag(Tab.more)
        }
    }
}
