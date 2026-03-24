import SwiftUI

/// Chat view for a single crew channel — supports real-time messaging.
struct CrewChannelChatView: View {
    let channel: CrewChannel

    @ObservedObject private var supabase = SupabaseService.shared
    @ObservedObject private var offlineCache = OfflineCacheService.shared
    @State private var messages: [CrewChannelMessage] = []
    @State private var newMessageText = ""
    @State private var isSending = false
    @State private var isLoading = true

    private var currentUserId: UUID? {
        supabase.currentUser?.id
    }

    var body: some View {
        ZStack {
            TGBackgroundView()

            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            if isLoading {
                                ProgressView()
                                    .tint(TGTheme.indigo)
                                    .padding(.top, 40)
                            } else if messages.isEmpty {
                                channelEmptyState
                            } else {
                                ForEach(messages) { message in
                                    CrewMessageRow(
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
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                scrollProxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input bar
                crewMessageInputBar
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMessages()
        }
    }

    // MARK: - Empty State

    private var channelEmptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: channel.channelType.icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Welcome to \(channel.name)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Be the first to send a message")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var crewMessageInputBar: some View {
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

    // MARK: - Data

    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }

        do {
            messages = try await CrewChatService.shared.fetchMessages(channelId: channel.id)
            offlineCache.cacheMessages(messages, channelId: channel.id)
        } catch {
            // Fall back to cached messages
            if let cached = offlineCache.cachedMessages(channelId: channel.id) {
                messages = cached
            }
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
            let sent = try await CrewChatService.shared.sendMessage(channelId: channel.id, text: savedText)
            messages.append(sent)
        } catch {
            newMessageText = savedText
        }
    }
}

// MARK: - Crew Message Row

struct CrewMessageRow: View {
    let message: CrewChannelMessage
    let isFromCurrentUser: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isFromCurrentUser { Spacer(minLength: 60) }

            if isFromCurrentUser == false {
                // Avatar
                ZStack {
                    Circle()
                        .fill(TGTheme.indigo.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Text(String(message.senderName.prefix(1)).uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(TGTheme.indigo)
                }
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 3) {
                if isFromCurrentUser == false {
                    HStack(spacing: 4) {
                        Text(message.senderName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let rank = message.senderRank {
                            Text(rank.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

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
