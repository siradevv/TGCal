import SwiftUI

/// Share roster with family/partners via iCal export or link.
struct SharedRosterView: View {
    @EnvironmentObject private var store: TGCalStore
    @ObservedObject private var sharedRosterService = SharedRosterService.shared
    @ObservedObject private var supabase = SupabaseService.shared

    @State private var isGeneratingICS = false
    @State private var icsFileURL: URL?
    @State private var isShowingShareSheet = false
    @State private var selectedMonthId: String?
    @State private var isCreatingLink = false
    @State private var linkLabel = ""

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Export as iCal
                    icsExportSection

                    // Active share links
                    if supabase.isAuthenticated {
                        shareLinksSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Share Roster")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingShareSheet) {
            if let url = icsFileURL {
                ShareSheetView(activityItems: [url])
            }
        }
        .task {
            if supabase.isAuthenticated {
                await sharedRosterService.fetchMyLinks()
            }
        }
    }

    // MARK: - iCal Export

    private var icsExportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TGSectionHeader(title: "Export Calendar", systemImage: "square.and.arrow.up")

            Text("Export your roster as an .ics calendar file that family and partners can subscribe to in any calendar app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.months.isEmpty {
                Text("No roster loaded to export.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Month selector
                Picker("Month", selection: $selectedMonthId) {
                    Text("Select month").tag(String?.none)
                    ForEach(store.months) { month in
                        Text(monthLabel(month)).tag(Optional(month.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(TGTheme.indigo)

                Button {
                    exportICS()
                } label: {
                    if isGeneratingICS {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Export .ics File", systemImage: "calendar.badge.plus")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(TGTheme.indigo)
                .disabled(selectedMonthId == nil || isGeneratingICS)
            }
        }
        .tgFrostedCard(cornerRadius: 16, verticalPadding: 14)
    }

    // MARK: - Share Links

    private var shareLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TGSectionHeader(title: "Active Links", systemImage: "link")

            if sharedRosterService.isLoading {
                ProgressView().tint(TGTheme.indigo)
            } else if sharedRosterService.activeLinks.isEmpty {
                Text("No active share links. Links allow others to view your schedule in real-time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sharedRosterService.activeLinks) { link in
                    linkRow(link)
                }
            }
        }
        .tgFrostedCard(cornerRadius: 16, verticalPadding: 14)
    }

    private func linkRow(_ link: SharedRosterLink) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(link.label)
                    .font(.subheadline.weight(.semibold))
                Text("Month: \(link.monthId)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let url = sharedRosterService.shareURL(for: link) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TGTheme.indigo)
                }
            }

            Button {
                Task {
                    try? await sharedRosterService.deactivateLink(link.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func monthLabel(_ month: RosterMonthRecord) -> String {
        var comps = DateComponents()
        comps.month = month.month
        comps.year = month.year
        let date = Calendar.roster.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        return formatter.string(from: date)
    }

    private func exportICS() {
        guard let monthId = selectedMonthId,
              let month = store.months.first(where: { $0.id == monthId }) else { return }

        isGeneratingICS = true
        defer { isGeneratingICS = false }

        if let url = sharedRosterService.generateICalFile(for: month) {
            icsFileURL = url
            isShowingShareSheet = true
        }
    }
}

// ShareSheetView is defined in OverviewView.swift
