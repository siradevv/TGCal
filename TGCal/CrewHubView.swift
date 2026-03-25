import SwiftUI

/// The Crew tab — a hub for community features: chat, layover guide, and crew pairing.
struct CrewHubView: View {
    @ObservedObject private var supabase = SupabaseService.shared

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
            .navigationTitle("Crew")
        }
    }

    private var authenticatedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Crew Chat section
                NavigationLink {
                    CrewChatListView()
                } label: {
                    featureCard(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Crew Chat",
                        subtitle: "Chat with fellow crew members",
                        color: TGTheme.indigo
                    )
                }
                .buttonStyle(.plain)

                // Layover Guide section
                NavigationLink {
                    LayoverGuideView()
                } label: {
                    featureCard(
                        icon: "map.fill",
                        title: "Layover Guide",
                        subtitle: "Crew tips for every destination",
                        color: TGTheme.mint
                    )
                }
                .buttonStyle(.plain)

                // Crew Pairing section
                NavigationLink {
                    CrewPairingView()
                } label: {
                    featureCard(
                        icon: "person.2.fill",
                        title: "Who's Flying With Me?",
                        subtitle: "See crew on your upcoming flights",
                        color: TGTheme.rose
                    )
                }
                .buttonStyle(.plain)

            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private func featureCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
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
        .tgFrostedCard(cornerRadius: 16, verticalPadding: 14)
    }
}
