import SwiftUI

/// List of all conversations (swap negotiations) for the current user.
struct ConversationsListView: View {
    @ObservedObject private var supabase = SupabaseService.shared
    @ObservedObject private var swapService = SwapService.shared

    @State private var isLoading = true
    @State private var profileCache: [UUID: UserProfile] = [:]
    @State private var selectedConversation: Conversation?

    private var currentUserId: UUID? {
        supabase.currentUser?.id
    }

    var body: some View {
        ZStack {
            TGBackgroundView()

            if isLoading {
                ProgressView()
                    .tint(TGTheme.indigo)
            } else if swapService.conversations.isEmpty {
                emptyState
            } else {
                conversationsList
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedConversation) { conversation in
            ChatView(conversation: conversation)
        }
        .task {
            await loadConversations()
        }
        .refreshable {
            await loadConversations()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No conversations yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Browse the Swap Board and message someone to get started")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var conversationsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(swapService.conversations) { conversation in
                    conversationRow(conversation)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            selectedConversation = conversation
        } label: {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(TGTheme.indigo.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.fill")
                        .font(.headline)
                        .foregroundStyle(TGTheme.indigo)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(otherUserDisplayName(for: conversation))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        if let lastAt = conversation.lastMessageAt {
                            Text(relativeTimeText(lastAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Status chip
                    statusChip(for: conversation)
                }

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
        .buttonStyle(.plain)
        .task {
            await cacheOtherProfile(for: conversation)
        }
    }

    private func statusChip(for conversation: Conversation) -> some View {
        HStack(spacing: 4) {
            switch conversation.status {
            case .confirmed:
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                Text("Confirmed")
                    .font(.caption2.weight(.semibold))
            case .cancelled:
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                Text("Cancelled")
                    .font(.caption2.weight(.semibold))
            case .active where conversation.initiatorConfirmed || conversation.ownerConfirmed:
                Image(systemName: "clock.fill")
                    .font(.caption2)
                Text("Pending confirmation")
                    .font(.caption2.weight(.semibold))
            default:
                EmptyView()
            }
        }
        .foregroundStyle(statusColor(for: conversation.status, hasPartialConfirm: conversation.initiatorConfirmed || conversation.ownerConfirmed))
    }

    private func statusColor(for status: ConversationStatus, hasPartialConfirm: Bool) -> Color {
        switch status {
        case .confirmed: return .green
        case .cancelled: return .red
        case .active where hasPartialConfirm: return .orange
        default: return .secondary
        }
    }

    // MARK: - Helpers

    private func otherUserDisplayName(for conversation: Conversation) -> String {
        guard let userId = currentUserId else { return "Unknown" }
        let otherId = conversation.otherParticipantId(currentUser: userId)
        return profileCache[otherId]?.displayName ?? "Crew Member"
    }

    private func cacheOtherProfile(for conversation: Conversation) async {
        guard let userId = currentUserId else { return }
        let otherId = conversation.otherParticipantId(currentUser: userId)
        guard profileCache[otherId] == nil else { return }

        if let profile = try? await SwapService.shared.fetchProfile(userId: otherId) {
            profileCache[otherId] = profile
        }
    }

    private func relativeTimeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadConversations() async {
        isLoading = swapService.conversations.isEmpty
        defer { isLoading = false }

        try? await swapService.fetchMyConversations()
    }
}
