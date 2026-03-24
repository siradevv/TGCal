import SwiftUI

/// In-app chat between two crew members about a flight swap.
struct ChatView: View {
    let conversation: Conversation

    @ObservedObject private var supabase = SupabaseService.shared
    @State private var messages: [ChatMessage] = []
    @State private var newMessageText = ""
    @State private var isSending = false
    @State private var isLoading = true
    @State private var otherUserName: String = "Crew Member"
    @State private var showConfirmSwap = false
    @State private var showCancelSwap = false
    @State private var isConfirming = false
    @State private var listing: SwapListing?

    private var currentUserId: UUID? {
        supabase.currentUser?.id
    }

    private var isTooCloseToDepart: Bool {
        guard let listing else { return false }
        return SwapService.shared.isSwappable(listing) == false
    }

    private var hasCurrentUserConfirmed: Bool {
        guard let userId = currentUserId else { return false }
        return conversation.hasUserConfirmed(userId)
    }

    var body: some View {
        ZStack {
            TGBackgroundView()

            VStack(spacing: 0) {
                // Swap status banner
                swapStatusBanner

                // Messages
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            if isLoading {
                                ProgressView()
                                    .tint(TGTheme.indigo)
                                    .padding(.top, 40)
                            } else if messages.isEmpty {
                                emptyState
                            } else {
                                ForEach(messages) { message in
                                    MessageBubble(
                                        message: message,
                                        isFromCurrentUser: message.senderId == currentUserId
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastMessage = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input bar
                messageInputBar
            }
        }
        .navigationTitle(otherUserName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                swapActionMenu
            }
        }
        .alert("Confirm Swap", isPresented: $showConfirmSwap) {
            Button("Confirm", role: .none) {
                Task { await confirmSwap() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Both parties must confirm. The actual swap is completed via Thai Airways internal systems.")
        }
        .alert("Cancel Swap", isPresented: $showCancelSwap) {
            Button("Cancel Swap", role: .destructive) {
                Task { await cancelSwap() }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This will cancel the swap confirmation. The listing will be re-opened.")
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Swap Status Banner

    @ViewBuilder
    private var swapStatusBanner: some View {
        switch conversation.status {
        case .confirmed:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                Text("Swap confirmed — complete via TG internal system")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.green)

        case .active where conversation.initiatorConfirmed || conversation.ownerConfirmed:
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                Text(hasCurrentUserConfirmed ? "Waiting for other party to confirm" : "Other party has confirmed — tap to confirm")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.orange)

        case .cancelled:
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                Text("Swap cancelled")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.8))

        default:
            EmptyView()
        }
    }

    // MARK: - Swap Action Menu

    private var swapActionMenu: some View {
        Menu {
            if conversation.status == .active && hasCurrentUserConfirmed == false {
                if isTooCloseToDepart {
                    Button {} label: {
                        Label("Too close to departure", systemImage: "clock.badge.exclamationmark")
                    }
                    .disabled(true)
                } else {
                    Button {
                        showConfirmSwap = true
                    } label: {
                        Label("Confirm Swap", systemImage: "checkmark.seal")
                    }
                }
            }

            if conversation.status == .active || conversation.status == .confirmed {
                Button(role: .destructive) {
                    showCancelSwap = true
                } label: {
                    Label("Cancel Swap", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(TGTheme.indigo)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Start the conversation")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Send a message to discuss the swap")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Message Input

    private var messageInputBar: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $newMessageText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(TGTheme.insetFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(TGTheme.insetStroke, lineWidth: 1)
                        )
                )

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? TGTheme.indigo : Color.secondary.opacity(0.3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            TGTheme.cardFill
                .shadow(color: TGTheme.cardShadow, radius: 8, x: 0, y: -4)
        )
    }

    private var canSend: Bool {
        isSending == false && newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // Load listing for 24-hour check
        listing = await SwapService.shared.fetchListing(id: conversation.listingId)

        // Load other user name
        if let userId = currentUserId {
            let otherId = conversation.otherParticipantId(currentUser: userId)
            if let profile = try? await SwapService.shared.fetchProfile(userId: otherId) {
                otherUserName = profile.displayName
            }
        }

        // Load messages
        do {
            messages = try await SwapService.shared.fetchMessages(conversationId: conversation.id)
            try? await SwapService.shared.markMessagesAsRead(conversationId: conversation.id)
        } catch {
            // Show empty state
        }
    }

    private func sendMessage() async {
        let text = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        isSending = true
        let savedText = text
        newMessageText = ""
        defer { isSending = false }

        do {
            let sent = try await SwapService.shared.sendMessage(conversationId: conversation.id, text: savedText)
            messages.append(sent)
        } catch {
            newMessageText = savedText
        }
    }

    private func confirmSwap() async {
        isConfirming = true
        defer { isConfirming = false }

        do {
            try await SwapService.shared.confirmSwap(conversationId: conversation.id)
            // Send a system-like message
            _ = try? await SwapService.shared.sendMessage(
                conversationId: conversation.id,
                text: "\(supabase.currentUser?.displayName ?? "I") confirmed the swap."
            )
            await loadData()
        } catch {
            // Handle error
        }
    }

    private func cancelSwap() async {
        do {
            try await SwapService.shared.cancelSwap(conversationId: conversation.id)
            _ = try? await SwapService.shared.sendMessage(
                conversationId: conversation.id,
                text: "\(supabase.currentUser?.displayName ?? "I") cancelled the swap."
            )
            await loadData()
        } catch {
            // Handle error
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool

    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer(minLength: 60) }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(isFromCurrentUser ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isFromCurrentUser ? TGTheme.indigo : TGTheme.cardFill)
                            .overlay(
                                isFromCurrentUser ? nil :
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(TGTheme.cardStroke, lineWidth: 1)
                            )
                    )

                if let sentAt = message.sentAt {
                    Text(timeText(sentAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if isFromCurrentUser == false { Spacer(minLength: 60) }
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
