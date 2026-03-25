import SwiftUI

/// Browse layover tips organized by destination, with crew-curated recommendations.
struct LayoverGuideView: View {
    @EnvironmentObject private var store: TGCalStore
    @ObservedObject private var layoverService = LayoverService.shared

    @State private var searchText = ""
    @State private var selectedAirport: String?
    @State private var isShowingAddTip = false

    /// All unique destination codes from the user's roster.
    private var rosterDestinations: [String] {
        var codes = Set<String>()
        for month in store.months {
            for detail in month.detailsByFlight.values {
                if let dest = detail.destination?.uppercased(), dest.isEmpty == false, dest != "BKK" {
                    codes.insert(dest)
                }
            }
        }
        return codes.sorted()
    }

    /// Popular TG destinations for users who haven't loaded a roster yet.
    private static let popularDestinations = [
        "NRT", "HND", "LHR", "CDG", "FRA", "SIN", "HKG", "ICN",
        "SYD", "MEL", "DEL", "BOM", "PEK", "PVG", "KUL", "CGK"
    ]

    private var displayDestinations: [String] {
        let base = rosterDestinations.isEmpty ? Self.popularDestinations : rosterDestinations
        if searchText.isEmpty { return base }
        return base.filter { code in
            let info = DestinationMetadata.info(for: code)
            return code.localizedCaseInsensitiveContains(searchText)
                || info.cityName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Search
                    searchBar

                    // Destinations grid
                    LazyVStack(spacing: 8) {
                        ForEach(displayDestinations, id: \.self) { code in
                            NavigationLink {
                                LayoverDestinationView(airportCode: code)
                            } label: {
                                destinationRow(code)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Layover Guide")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddTip = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(TGTheme.indigo)
                }
            }
        }
        .sheet(isPresented: $isShowingAddTip) {
            AddLayoverTipView()
                .environmentObject(store)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Search destinations...", text: $searchText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            if searchText.isEmpty == false {
                Button {
                    searchText = ""
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
    }

    // MARK: - Destination Row

    private func destinationRow(_ code: String) -> some View {
        let info = DestinationMetadata.info(for: code)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TGTheme.indigo.opacity(0.1))
                    .frame(width: 44, height: 44)
                Text(code)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TGTheme.indigo)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(info.cityName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Label(info.currencyCode, systemImage: "banknote")
                    Label(info.plugType.displayLabel, systemImage: "powerplug")
                }
                .font(.caption2)
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
}

// MARK: - Layover Destination View

/// Shows all tips for a specific airport, organized by category.
struct LayoverDestinationView: View {
    let airportCode: String

    @ObservedObject private var layoverService = LayoverService.shared
    @ObservedObject private var offlineCache = OfflineCacheService.shared
    @State private var selectedCategory: LayoverCategory?
    @State private var isShowingAddTip = false

    private var info: DestinationInfo {
        DestinationMetadata.info(for: airportCode)
    }

    private var filteredTips: [LayoverTip] {
        var tips = layoverService.tips
        if tips.isEmpty, let cached = offlineCache.cachedLayoverTips(airportCode: airportCode) {
            tips = cached
        }
        if let category = selectedCategory {
            return tips.filter { $0.category == category }
        }
        return tips
    }

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Destination quick info
                    destinationInfoCard

                    // Category filter
                    categoryFilter

                    // Tips list
                    if layoverService.isLoading {
                        HStack {
                            Spacer()
                            ProgressView().tint(TGTheme.indigo)
                            Spacer()
                        }
                        .padding(.top, 30)
                    } else if filteredTips.isEmpty {
                        emptyTipsState
                    } else {
                        ForEach(filteredTips) { tip in
                            LayoverTipCard(tip: tip)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(info.cityName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddTip = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(TGTheme.indigo)
                }
            }
        }
        .sheet(isPresented: $isShowingAddTip) {
            AddLayoverTipView(preselectedAirport: airportCode)
        }
        .task {
            await layoverService.fetchTips(airportCode: airportCode, category: selectedCategory)
            if layoverService.tips.isEmpty == false {
                offlineCache.cacheLayoverTips(layoverService.tips, airportCode: airportCode)
                await layoverService.loadUserVotes(for: layoverService.tips.map(\.id))
            }
        }
    }

    private var destinationInfoCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(info.currencyCode)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(TGTheme.indigo.opacity(0.12))
                        )
                        .foregroundStyle(TGTheme.indigo)

                    Text("\(info.plugType.displayLabel) \(info.voltage)V")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(.orange.opacity(0.12))
                        )
                        .foregroundStyle(.orange)
                }

                Text(info.timeZoneIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(airportCode)
                .font(.title2.weight(.bold))
                .foregroundStyle(TGTheme.indigo)
        }
        .tgFrostedCard(cornerRadius: 14, verticalPadding: 12)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(nil, label: "All")
                ForEach(LayoverCategory.allCases) { cat in
                    categoryChip(cat, label: cat.displayName)
                }
            }
        }
    }

    private func categoryChip(_ category: LayoverCategory?, label: String) -> some View {
        let isActive = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
            }
            Task {
                await layoverService.fetchTips(airportCode: airportCode, category: category)
            }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isActive ? TGTheme.indigo : TGTheme.controlFill)
                )
                .foregroundStyle(isActive ? .white : .primary)
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.clear : TGTheme.controlStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var emptyTipsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No tips yet for \(info.cityName)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Be the first to share a recommendation!")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Button {
                isShowingAddTip = true
            } label: {
                Label("Add a Tip", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(TGTheme.indigo)
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Layover Tip Card

struct LayoverTipCard: View {
    let tip: LayoverTip

    @ObservedObject private var layoverService = LayoverService.shared
    @State private var isVoting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: tip.category.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TGTheme.indigo)

                Text(tip.category.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TGTheme.indigo)

                Spacer()

                Text(tip.authorName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(tip.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(tip.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            HStack(spacing: 16) {
                Spacer()

                Button {
                    Task { await vote(isUpvote: true) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.caption.weight(.semibold))
                        Text("\(tip.upvotes)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(layoverService.hasVoted(tipId: tip.id) ? TGTheme.indigo : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isVoting || layoverService.hasVoted(tipId: tip.id))

                Button {
                    Task { await vote(isUpvote: false) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.caption.weight(.semibold))
                        Text("\(tip.downvotes)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(layoverService.hasVoted(tipId: tip.id) ? .red.opacity(0.6) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isVoting || layoverService.hasVoted(tipId: tip.id))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

    private func vote(isUpvote: Bool) async {
        isVoting = true
        defer { isVoting = false }
        _ = try? await layoverService.vote(tipId: tip.id, isUpvote: isUpvote)
    }
}

// MARK: - Add Layover Tip View

struct AddLayoverTipView: View {
    var preselectedAirport: String?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseService.shared

    @State private var airportCode = ""
    @State private var selectedCategory: LayoverCategory = .general
    @State private var title = ""
    @State private var tipBody = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Airport code
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Airport Code")
                                .font(.subheadline.weight(.semibold))
                            TextField("e.g. NRT", text: $airportCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
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

                        // Category
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Category")
                                .font(.subheadline.weight(.semibold))
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(LayoverCategory.allCases) { cat in
                                    Label(cat.displayName, systemImage: cat.icon)
                                        .tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(TGTheme.indigo)
                        }

                        // Title
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title")
                                .font(.subheadline.weight(.semibold))
                            TextField("Short summary", text: $title)
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

                        // Body
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Details")
                                .font(.subheadline.weight(.semibold))
                            TextEditor(text: $tipBody)
                                .font(.subheadline)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 100)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(TGTheme.insetFill)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(TGTheme.insetStroke, lineWidth: 1)
                                        )
                                )
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await submitTip() }
                        } label: {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Submit Tip")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TGTheme.indigo)
                        .disabled(isSubmitting || !isValid)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Add Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let preselectedAirport {
                    airportCode = preselectedAirport
                }
            }
        }
    }

    private var isValid: Bool {
        airportCode.count == 3 && title.isEmpty == false && tipBody.isEmpty == false
    }

    private func submitTip() async {
        guard let user = supabase.currentUser else {
            errorMessage = "You must be signed in."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let newTip = NewLayoverTip(
            airportCode: airportCode.uppercased(),
            category: selectedCategory,
            title: title,
            body: tipBody,
            authorId: user.id,
            authorName: user.displayName
        )

        do {
            _ = try await LayoverService.shared.createTip(newTip)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
