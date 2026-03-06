import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var isShowingPrivacyPolicy = false

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                VStack(spacing: 0) {
                    List {
                        Section {
                            VStack(spacing: 0) {
                                Button {
                                    isShowingPrivacyPolicy = true
                            } label: {
                                settingsRow(
                                    title: "Privacy Policy"
                                )
                            }
                            .buttonStyle(.plain)

                                Divider()

                                Button {
                                    if let url = URL(string: "mailto:tgcal.app@gmail.com?subject=TGCal%20Support") {
                                        openURL(url)
                                    }
                            } label: {
                                settingsRow(
                                    title: "Contact Support"
                                )
                            }
                            .buttonStyle(.plain)
                            }
                            .tgFrostedCard(cornerRadius: 18, verticalPadding: 8)
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } header: {
                            TGSectionHeader(title: "Support", systemImage: "questionmark.circle")
                                .textCase(nil)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)

                    Text(appVersionBuildText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $isShowingPrivacyPolicy) {
                PrivacyPolicyView()
            }
        }
    }

    private var appVersionBuildText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "Version \(shortVersion) (\(build))"
    }

    private func settingsRow(title: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
