import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: TGCalStore
    @State private var isShowingMonthPicker = false

    let importRosterAction: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Active Month") {
                    Text(activeMonthTitle)
                        .font(.headline)

                    Button("Import roster") {
                        importRosterAction()
                    }

                    Button("Choose Month") {
                        isShowingMonthPicker = true
                    }
                    .disabled(store.months.isEmpty)
                }
            }
            .navigationTitle("Overview")
            .sheet(isPresented: $isShowingMonthPicker) {
                monthPickerSheet
            }
        }
    }

    private var sortedMonths: [RosterMonthRecord] {
        store.months.sorted { lhs, rhs in
            if lhs.year != rhs.year {
                return lhs.year > rhs.year
            }
            if lhs.month != rhs.month {
                return lhs.month > rhs.month
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var activeMonthTitle: String {
        guard let active = store.activeMonth else {
            return "No roster loaded"
        }

        var comps = DateComponents()
        comps.calendar = .roster
        comps.timeZone = rosterTimeZone
        comps.year = active.year
        comps.month = active.month
        comps.day = 1

        let date = comps.date ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private var monthPickerSheet: some View {
        NavigationStack {
            List(sortedMonths) { month in
                Button {
                    store.setActiveMonth(month.id)
                    isShowingMonthPicker = false
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(monthTitle(for: month))
                                .foregroundStyle(.primary)
                            Text(month.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.activeMonthId == month.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Select Month")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingMonthPicker = false
                    }
                }
            }
        }
    }

    private func monthTitle(for month: RosterMonthRecord) -> String {
        var comps = DateComponents()
        comps.calendar = .roster
        comps.timeZone = rosterTimeZone
        comps.year = month.year
        comps.month = month.month
        comps.day = 1

        let date = comps.date ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}
