import SwiftUI

/// Shows the current user's swap listings with ability to cancel them.
struct MyListingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var swapService = SwapService.shared

    @State private var isLoading = true
    @State private var listingToCancel: SwapListing?

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                if isLoading {
                    ProgressView()
                        .tint(TGTheme.indigo)
                } else if swapService.myListings.isEmpty {
                    emptyState
                } else {
                    listingsView
                }
            }
            .navigationTitle("My Listings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Cancel Listing", isPresented: Binding(
                get: { listingToCancel != nil },
                set: { if !$0 { listingToCancel = nil } }
            )) {
                Button("Cancel Listing", role: .destructive) {
                    if let listing = listingToCancel {
                        Task { await cancelListing(listing) }
                    }
                }
                Button("Keep", role: .cancel) { listingToCancel = nil }
            } message: {
                Text("This listing will be removed from the Swap Board.")
            }
            .task {
                await loadMyListings()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No listings")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Flights you post for swap will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private var listingsView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(swapService.myListings) { listing in
                    myListingCard(listing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func myListingCard(_ listing: SwapListing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.flightCode)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(TGTheme.indigo)
                    Text(listing.routeText)
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                statusBadge(listing.status)
            }

            Text(listing.displayDate)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let note = listing.note, note.isEmpty == false {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if listing.status == .open {
                Button(role: .destructive) {
                    listingToCancel = listing
                } label: {
                    Text("Cancel Listing")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tgOverviewCard(cornerRadius: 16, verticalPadding: 12)
    }

    private func statusBadge(_ status: SwapStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(statusColor(status).opacity(0.15))
            )
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: SwapStatus) -> Color {
        switch status {
        case .open: return .green
        case .pending: return .orange
        case .confirmed: return TGTheme.indigo
        case .cancelled: return .red
        }
    }

    private func loadMyListings() async {
        isLoading = swapService.myListings.isEmpty
        defer { isLoading = false }
        try? await swapService.fetchMyListings()
    }

    private func cancelListing(_ listing: SwapListing) async {
        try? await swapService.cancelListing(listing.id)
        listingToCancel = nil
    }
}
