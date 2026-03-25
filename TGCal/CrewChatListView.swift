import SwiftUI

/// List of all crew chat channels.
struct CrewChatListView: View {
    @ObservedObject private var chatService = CrewChatService.shared
    @ObservedObject private var offlineCache = OfflineCacheService.shared
    @State private var selectedChannel: CrewChannel?

    var body: some View {
        ZStack {
            TGBackgroundView()

            if chatService.isLoadingChannels {
                ProgressView()
                    .tint(TGTheme.indigo)
            } else if displayChannels.isEmpty {
                emptyState
            } else {
                channelsList
            }
        }
        .navigationTitle("Crew Chat")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedChannel) { channel in
            CrewChannelChatView(channel: channel)
        }
        .task {
            await chatService.fetchChannels()
            if chatService.channels.isEmpty == false {
                offlineCache.cacheChannels(chatService.channels)
            }
        }
        .refreshable {
            await chatService.fetchChannels()
        }
    }

    private var displayChannels: [CrewChannel] {
        if chatService.channels.isEmpty && offlineCache.isOnline == false {
            return offlineCache.cachedChannels() ?? []
        }
        return chatService.channels
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No channels yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Channels will appear here once created by admins")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var channelsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(ChannelType.allCases, id: \.self) { type in
                    let filtered = displayChannels.filter { $0.channelType == type }
                    if filtered.isEmpty == false {
                        Section {
                            ForEach(filtered) { channel in
                                channelRow(channel)
                            }
                        } header: {
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                            .padding(.leading, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func channelRow(_ channel: CrewChannel) -> some View {
        Button {
            selectedChannel = channel
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(TGTheme.indigo.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: channel.channelType.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TGTheme.indigo)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(channel.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        if let lastAt = channel.lastMessageAt {
                            Text(relativeTime(lastAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let lastMessage = channel.lastMessageText {
                        Text(lastMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let desc = channel.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
