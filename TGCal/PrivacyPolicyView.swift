import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Privacy Policy")
                            .font(.title2.weight(.bold))
                    }
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 0) {
                        policySection(
                            title: "Overview",
                            paragraphs: [
                                "TGCal helps you import roster PDFs, manage flight details, and add flights to Apple Calendar. Most processing is done on your device."
                            ]
                        )

                        subtleDivider

                        policySection(
                            title: "Data Stored on Your Device",
                            bullets: [
                                "Imported roster month data.",
                                "Briefing notes you add.",
                                "No account is required."
                            ]
                        )

                        subtleDivider

                        policySection(
                            title: "Calendar Access",
                            paragraphs: [
                                "TGCal requests Calendar permission only when you use calendar features."
                            ],
                            bullets: [
                                "TGCal adds events only after you explicitly choose to add them.",
                                "When updating an existing calendar, TGCal may remove and re-add TGCal-created events for the selected month."
                            ]
                        )

                        subtleDivider

                        policySection(
                            title: "Online Services",
                            paragraphs: [
                                "Some features call third-party services:"
                            ],
                            bullets: [
                                "Open-Meteo for weather.",
                                "Exchange-rate API for THB conversion.",
                                "Aviationstack for flight details such as aircraft and gate."
                            ]
                        )

                        subtleDivider

                        policySection(
                            title: "Contact",
                            paragraphs: [
                                "For privacy questions, contact tgcal.app@gmail.com."
                            ]
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(TGTheme.cardFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(TGTheme.cardStroke, lineWidth: 1.1)
                            )
                            .shadow(color: TGTheme.cardShadow, radius: 12, x: 0, y: 8)
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(title: String, paragraphs: [String] = [], bullets: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(TGTheme.indigo)

            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(bullet)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var subtleDivider: some View {
        Rectangle()
            .fill(TGTheme.insetStroke.opacity(0.55))
            .frame(height: 1)
    }
}
