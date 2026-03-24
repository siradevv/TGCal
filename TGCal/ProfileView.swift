import SwiftUI

/// User profile editor — accessible from Settings.
struct ProfileView: View {
    @ObservedObject private var supabase = SupabaseService.shared

    @State private var displayName: String = ""
    @State private var crewRank: CrewRank = .cabin
    @State private var isSaving = false
    @State private var showSaved = false
    @State private var showSignOutConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Profile header
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(TGTheme.indigo.opacity(0.15))
                                .frame(width: 64, height: 64)
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(TGTheme.indigo)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(supabase.currentUser?.displayName ?? "Crew Member")
                                .font(.title3.weight(.semibold))
                            Text(supabase.currentUser?.crewRank.displayName ?? "Cabin Crew")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tgOverviewCard(verticalPadding: 16)

                    // Edit form
                    VStack(alignment: .leading, spacing: 12) {
                        TGSectionHeader(title: "Edit Profile", systemImage: "pencil")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Display Name")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("Your name", text: $displayName)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(TGTheme.insetFill)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(TGTheme.insetStroke, lineWidth: 1)
                                        )
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Crew Rank")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("Rank", selection: $crewRank) {
                                ForEach(CrewRank.allCases) { rank in
                                    Text(rank.displayName).tag(rank)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await saveProfile() }
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else if showSaved {
                                    Label("Saved", systemImage: "checkmark")
                                        .font(.subheadline.weight(.semibold))
                                } else {
                                    Text("Save Changes")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TGTheme.indigo)
                        .disabled(isSaving)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .tgOverviewCard(verticalPadding: 14)

                    // Sign out
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign Out", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                Task { try? await supabase.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if let profile = supabase.currentUser {
                displayName = profile.displayName
                crewRank = profile.crewRank
            }
        }
    }

    private func saveProfile() async {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2 else {
            errorMessage = "Name must be at least 2 characters"
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await supabase.updateProfile(displayName: name, crewRank: crewRank)
            showSaved = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSaved = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
