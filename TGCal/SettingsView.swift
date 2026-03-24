import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var isShowingPrivacyPolicy = false
    @AppStorage("reminders_enabled") private var remindersEnabled = true
    @AppStorage("reminder_12h") private var reminder12h = true
    @AppStorage("reminder_3h") private var reminder3h = true

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                VStack(spacing: 0) {
                    List {
                        Section {
                            VStack(spacing: 0) {
                                Toggle(isOn: $remindersEnabled) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Duty Reminders")
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text("Get notified before flights")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .tint(TGTheme.indigo)
                                .padding(.vertical, 6)
                                .onChange(of: remindersEnabled) { _, enabled in
                                    if enabled {
                                        NotificationService.shared.requestPermission()
                                    } else {
                                        NotificationService.shared.cancelAllReminders()
                                    }
                                }

                                if remindersEnabled {
                                    Divider()
                                        .overlay(TGTheme.insetStroke.opacity(0.55))

                                    Toggle("12 hours before", isOn: $reminder12h)
                                        .font(.subheadline)
                                        .tint(TGTheme.indigo)
                                        .padding(.vertical, 6)

                                    Divider()
                                        .overlay(TGTheme.insetStroke.opacity(0.55))

                                    Toggle("3 hours before", isOn: $reminder3h)
                                        .font(.subheadline)
                                        .tint(TGTheme.indigo)
                                        .padding(.vertical, 6)
                                }
                            }
                            .tgFrostedCard(cornerRadius: 18, verticalPadding: 8)
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } header: {
                            TGSectionHeader(title: "Notifications", systemImage: "bell.badge")
                                .textCase(nil)
                        }

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
                                    .overlay(TGTheme.insetStroke.opacity(0.55))

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
        .padding(.vertical, 11)
    }
}
