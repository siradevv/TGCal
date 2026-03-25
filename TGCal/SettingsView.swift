import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingProfile = false
    @ObservedObject private var supabase = SupabaseService.shared
    @AppStorage("reminders_enabled") private var remindersEnabled = true
    @AppStorage("reminder_12h") private var reminder12h = true
    @AppStorage("reminder_3h") private var reminder3h = true
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeletingAccount = false

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                VStack(spacing: 0) {
                    List {
                        if supabase.isAuthenticated {
                            Section {
                                VStack(spacing: 0) {
                                    Button {
                                        isShowingProfile = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(TGTheme.indigo.opacity(0.15))
                                                    .frame(width: 40, height: 40)
                                                Image(systemName: "person.fill")
                                                    .font(.headline)
                                                    .foregroundStyle(TGTheme.indigo)
                                            }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(supabase.currentUser?.displayName ?? "Crew Member")
                                                    .font(.body.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                Text(supabase.currentUser?.crewRank.displayName ?? "Cabin Crew")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .tgFrostedCard(cornerRadius: 18, verticalPadding: 8)
                                .padding(.vertical, 2)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            } header: {
                                TGSectionHeader(title: "Account", systemImage: "person.circle")
                                    .textCase(nil)
                            }
                        }

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

                        if supabase.isAuthenticated {
                            Section {
                                VStack(spacing: 0) {
                                    Button {
                                        Task {
                                            try? await supabase.signOut()
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text("Sign Out")
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 11)
                                    }
                                    .buttonStyle(.plain)

                                    Divider()
                                        .overlay(TGTheme.insetStroke.opacity(0.55))

                                    Button {
                                        isShowingDeleteConfirmation = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text("Delete Account")
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.red)
                                            Spacer()
                                            if isDeletingAccount {
                                                ProgressView()
                                                    .tint(.red)
                                            } else {
                                                Image(systemName: "trash")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                        .padding(.vertical, 11)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isDeletingAccount)
                                }
                                .tgFrostedCard(cornerRadius: 18, verticalPadding: 8)
                                .padding(.vertical, 2)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            } header: {
                                TGSectionHeader(title: "Account Actions", systemImage: "person.badge.minus")
                                    .textCase(nil)
                            }
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
            .navigationDestination(isPresented: $isShowingProfile) {
                ProfileView()
            }
            .alert("Error", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "Failed to delete account. Please try again.")
            }
            .alert("Delete Account", isPresented: $isShowingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task { await performDeleteAccount() }
                }
            } message: {
                Text("Are you sure you want to permanently delete your account? This will remove all your data including roster history, swap listings, and messages. This action cannot be undone.")
            }
        }
    }

    @State private var deleteErrorMessage: String?

    private func performDeleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await supabase.deleteAccount()
        } catch {
            deleteErrorMessage = error.localizedDescription
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
