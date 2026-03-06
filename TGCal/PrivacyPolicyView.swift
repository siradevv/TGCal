import SwiftUI

struct PrivacyPolicyView: View {
    private let lastUpdated = "March 6, 2026"

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TGCal Privacy Policy")
                            .font(.title2.weight(.bold))
                        Text("Last updated: \(lastUpdated)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .tgFrostedCard(cornerRadius: 18, verticalPadding: 12)

                    policySection(
                        title: "Overview",
                        paragraphs: [
                            "TGCal helps users import roster PDFs, manage flight details, estimate earnings, prepare destination briefings, and add flights to Apple Calendar."
                        ]
                    )

                    policySection(
                        title: "Data We Process",
                        bullets: [
                            "Roster PDF parsing is performed on-device in the app.",
                            "The app stores imported roster month data on your device.",
                            "Briefing notes you add are stored on your device.",
                            "TGCal does not require account creation."
                        ]
                    )

                    policySection(
                        title: "Calendar Access",
                        paragraphs: [
                            "TGCal requests Calendar permission only when you use calendar features."
                        ],
                        bullets: [
                            "TGCal adds events only after you explicitly choose to add them.",
                            "When adding to an existing calendar, TGCal may remove TGCal-imported events for the selected month and then add updated flights for that same month.",
                            "TGCal does not intentionally remove your non-TGCal personal events."
                        ]
                    )

                    policySection(
                        title: "Network Services",
                        paragraphs: [
                            "Some features use network requests to third-party services:"
                        ],
                        bullets: [
                            "Open-Meteo for destination weather and arrival conditions (latitude/longitude and time-related query parameters).",
                            "Exchange rate API for THB currency conversion rates.",
                            "Aviationstack for live flight operational data such as aircraft and gate details (for example flight code, route, and service date).",
                            "TGCal does not run advertising SDKs and does not sell personal data."
                        ]
                    )

                    policySection(
                        title: "Data Storage and Retention",
                        bullets: [
                            "App data is stored locally on your device unless explicitly written to your Apple Calendar via your action.",
                            "Calendar events added by TGCal are stored in your selected calendar account according to Apple Calendar behavior.",
                            "You can remove app data by deleting the app and can remove calendar entries from Calendar at any time."
                        ]
                    )

                    policySection(
                        title: "Security Note",
                        paragraphs: [
                            "TGCal is designed to minimize data collection and process as much as possible on-device. No method of transmission or storage is guaranteed to be 100% secure."
                        ]
                    )

                    policySection(
                        title: "Children's Privacy",
                        paragraphs: [
                            "TGCal is not directed to children under 13 and does not knowingly collect personal information from children."
                        ]
                    )

                    policySection(
                        title: "Contact",
                        paragraphs: [
                            "For privacy questions, contact tgcal.app@gmail.com."
                        ]
                    )

                    policySection(
                        title: "Policy Changes",
                        paragraphs: [
                            "This policy may be updated from time to time. The \"Last updated\" date at the top indicates the latest revision."
                        ]
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Privacy Policy")
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
        .tgFrostedCard(cornerRadius: 18, verticalPadding: 12)
    }
}

