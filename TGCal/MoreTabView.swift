import SwiftUI

/// The More tab — a clean hub for Logbook, Settings, Commute Tracker, and Share Roster.
struct MoreTabView: View {
    @EnvironmentObject private var store: TGCalStore
    @ObservedObject private var supabase = SupabaseService.shared
    @ObservedObject private var offlineCache = OfflineCacheService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Account section
                        if supabase.isAuthenticated {
                            accountCard
                        }

                        // Feature cards
                        NavigationLink {
                            LogbookView()
                                .environmentObject(store)
                        } label: {
                            moreRow(
                                icon: "chart.bar.xaxis",
                                title: "Logbook",
                                subtitle: "Flight hours, earnings & stats",
                                color: TGTheme.indigo
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            CommuteTrackerView()
                        } label: {
                            moreRow(
                                icon: "car.side",
                                title: "Commute Tracker",
                                subtitle: "Track travel to base",
                                color: .orange
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SharedRosterView()
                                .environmentObject(store)
                        } label: {
                            moreRow(
                                icon: "square.and.arrow.up",
                                title: "Share Roster",
                                subtitle: "Share schedule with family",
                                color: .green
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SettingsView()
                                .environmentObject(store)
                        } label: {
                            moreRow(
                                icon: "gearshape",
                                title: "Settings",
                                subtitle: "Notifications, account & support",
                                color: .secondary
                            )
                        }
                        .buttonStyle(.plain)

                        // Sync status
                        syncStatusCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("More")
        }
    }

    // MARK: - Account Card

    private var accountCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(TGTheme.indigo.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.fill")
                    .font(.headline)
                    .foregroundStyle(TGTheme.indigo)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(supabase.currentUser?.displayName ?? "Crew Member")
                    .font(.body.weight(.semibold))
                Text(supabase.currentUser?.crewRank.displayName ?? "Cabin Crew")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .tgFrostedCard(cornerRadius: 16, verticalPadding: 12)
    }

    // MARK: - Feature Row

    private func moreRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TGTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TGTheme.cardStroke, lineWidth: 1)
                )
                .shadow(color: TGTheme.cardShadow, radius: 8, x: 0, y: 4)
        )
    }

    // MARK: - Sync Status

    private var syncStatusCard: some View {
        HStack(spacing: 8) {
            Image(systemName: offlineCache.isOnline ? "wifi" : "wifi.slash")
                .font(.caption)
                .foregroundStyle(offlineCache.isOnline ? .green : .orange)

            Text(offlineCache.isOnline ? "Online" : "Offline — cached data available")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Synced \(offlineCache.lastSyncText)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TGTheme.insetFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TGTheme.insetStroke, lineWidth: 1)
                )
        )
    }
}
