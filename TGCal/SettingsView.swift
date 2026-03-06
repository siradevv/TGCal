import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                List {
                    Section {
                        Button {
                            if let url = URL(string: "https://tgcalapp.github.io/privacy-policy.html") {
                                openURL(url)
                            }
                        } label: {
                            settingsRow(
                                title: "Privacy Policy",
                                subtitle: "Read how TGCal handles your data"
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let url = URL(string: "mailto:tgcal.app@gmail.com?subject=TGCal%20Support") {
                                openURL(url)
                            }
                        } label: {
                            settingsRow(
                                title: "Contact Support",
                                subtitle: "Send feedback or report an issue"
                            )
                        }
                        .buttonStyle(.plain)
                    } header: {
                        TGSectionHeader(title: "Support", systemImage: "questionmark.circle")
                            .textCase(nil)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Settings")
        }
    }

    private func settingsRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
