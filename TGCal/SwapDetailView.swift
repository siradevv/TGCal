import SwiftUI

/// Detail view for a swap listing — shows flight info and lets users initiate a chat.
struct SwapDetailView: View {
    let listing: SwapListing

    @ObservedObject private var supabase = SupabaseService.shared
    @State private var isStartingChat = false
    @State private var navigateToChat: Conversation?
    @State private var posterProfile: UserProfile?
    @State private var errorMessage: String?

    private var isOwnListing: Bool {
        supabase.currentUser?.id == listing.postedBy
    }

    private var isTooCloseToDepart: Bool {
        SwapService.shared.isSwappable(listing) == false
    }

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Flight info card
                    VStack(alignment: .leading, spacing: 12) {
                        TGSectionHeader(title: "Flight Details", systemImage: "airplane")

                        detailRow(title: "Flight", value: listing.flightCode)
                        Divider()
                        detailRow(title: "Route", value: listing.routeText)
                        Divider()
                        detailRow(title: "Date", value: listing.displayDate)

                        if let time = listing.departureTime {
                            Divider()
                            detailRow(title: "Departure", value: time)
                        }
                    }
                    .tgOverviewCard(verticalPadding: 14)

                    // Note
                    if let note = listing.note, note.isEmpty == false {
                        VStack(alignment: .leading, spacing: 8) {
                            TGSectionHeader(title: "Note")
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .tgOverviewCard(verticalPadding: 12)
                    }

                    // Posted by
                    VStack(alignment: .leading, spacing: 10) {
                        TGSectionHeader(title: "Posted By", systemImage: "person.circle")

                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(TGTheme.indigo.opacity(0.6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(listing.postedByName)
                                    .font(.subheadline.weight(.semibold))

                                if let profile = posterProfile {
                                    Text(profile.crewRank.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .tgOverviewCard(verticalPadding: 12)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Action button
                    if isOwnListing == false {
                        if isTooCloseToDepart {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .foregroundStyle(.orange)
                                Text("Swaps must be initiated at least 24 hours before departure")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        } else {
                            Button {
                                Task { await startChat() }
                            } label: {
                                Group {
                                    if isStartingChat {
                                        ProgressView().tint(.white)
                                    } else {
                                        Label("Message About This Swap", systemImage: "bubble.left.fill")
                                            .font(.headline.weight(.semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(TGTheme.indigo)
                            .disabled(isStartingChat)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("This is your listing")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Swap Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $navigateToChat) { conversation in
            ChatView(conversation: conversation)
        }
        .task {
            await loadPosterProfile()
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minHeight: 28)
    }

    private func startChat() async {
        isStartingChat = true
        errorMessage = nil
        defer { isStartingChat = false }

        do {
            let conversation = try await SwapService.shared.startConversation(listing: listing)
            navigateToChat = conversation
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPosterProfile() async {
        do {
            posterProfile = try await SwapService.shared.fetchProfile(userId: listing.postedBy)
        } catch {
            // Non-critical
        }
    }
}

extension Conversation: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
