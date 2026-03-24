import SwiftUI

/// Main swap board — browse, search, and filter available flight swaps.
struct SwapBoardView: View {
    @ObservedObject private var supabase = SupabaseService.shared
    @ObservedObject private var swapService = SwapService.shared

    @State private var searchText = ""
    @State private var filterDate: Date?
    @State private var isShowingFilters = false
    @State private var isShowingPostSheet = false
    @State private var isShowingMyListings = false
    @State private var isShowingConversations = false
    @State private var isLoading = false
    @State private var selectedListing: SwapListing?

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                if supabase.isAuthenticated {
                    authenticatedContent
                } else {
                    AuthView()
                }
            }
            .navigationTitle("Swap Board")
            .toolbar {
                if supabase.isAuthenticated {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isShowingConversations = true
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .foregroundStyle(TGTheme.indigo)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                isShowingPostSheet = true
                            } label: {
                                Label("Post a Swap", systemImage: "plus.circle")
                            }
                            Button {
                                isShowingMyListings = true
                            } label: {
                                Label("My Listings", systemImage: "list.bullet")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(TGTheme.indigo)
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingPostSheet) {
                PostSwapView()
            }
            .sheet(isPresented: $isShowingMyListings) {
                MyListingsView()
            }
            .navigationDestination(isPresented: $isShowingConversations) {
                ConversationsListView()
            }
            .navigationDestination(item: $selectedListing) { listing in
                SwapDetailView(listing: listing)
            }
            .task {
                await supabase.restoreSession()
            }
        }
    }

    // MARK: - Authenticated Content

    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            // Filter chips
            filterChips

            // Listings
            if isLoading {
                Spacer()
                ProgressView()
                    .tint(TGTheme.indigo)
                Spacer()
            } else if swappableListings.isEmpty {
                emptyState
            } else {
                listingsScrollView
            }
        }
        .task {
            await loadListings()
        }
        .refreshable {
            await loadListings()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Search flights, routes...", text: $searchText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await loadListings() }
                    }

                if searchText.isEmpty == false {
                    Button {
                        searchText = ""
                        Task { await loadListings() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TGTheme.insetFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TGTheme.insetStroke, lineWidth: 1)
                    )
            )

            Button {
                withAnimation { isShowingFilters.toggle() }
            } label: {
                Image(systemName: isShowingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundStyle(TGTheme.indigo)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var filterChips: some View {
        Group {
            if isShowingFilters {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        DatePicker(
                            "From",
                            selection: Binding(
                                get: { filterDate ?? Date() },
                                set: { filterDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .font(.subheadline)

                        if filterDate != nil {
                            Button("Clear") {
                                filterDate = nil
                                Task { await loadListings() }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TGTheme.indigo)
                        }
                    }

                    Button {
                        Task { await loadListings() }
                    } label: {
                        Text("Apply Filters")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TGTheme.indigo)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "airplane.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No swaps available")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Be the first to post a flight swap!")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Button {
                isShowingPostSheet = true
            } label: {
                Label("Post a Swap", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(TGTheme.indigo)

            Spacer()
        }
    }

    /// Only show listings where departure is >24 hours away.
    private var swappableListings: [SwapListing] {
        swapService.listings.filter { swapService.isSwappable($0) }
    }

    private var listingsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(swappableListings) { listing in
                    SwapListingCard(listing: listing) {
                        selectedListing = listing
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Data Loading

    private func loadListings() async {
        isLoading = swapService.listings.isEmpty
        defer { isLoading = false }

        do {
            try await swapService.fetchOpenListings(
                dateFrom: filterDate,
                searchText: searchText.isEmpty ? nil : searchText
            )
        } catch {
            // Silent failure — listings stay empty
        }
    }
}

// MARK: - Swap Listing Card

struct SwapListingCard: View {
    let listing: SwapListing
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(listing.flightCode)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(TGTheme.indigo)

                        Text(listing.routeText)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(listing.displayDate)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let time = listing.departureTime {
                            Text("DEP \(time)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                if let note = listing.note, note.isEmpty == false {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(listing.postedByName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tgOverviewCard(cornerRadius: 16, verticalPadding: 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NavigationDestination conformance

extension SwapListing: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
