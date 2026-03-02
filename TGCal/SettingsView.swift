import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section("Support") {
                    Button("Privacy Policy") {
                        if let url = URL(string: "https://tgcalapp.github.io/privacy-policy.html") {
                            openURL(url)
                        }
                    }

                    Button("Contact Support") {
                        if let url = URL(string: "mailto:tgcal.app@gmail.com?subject=TGCal%20Support") {
                            openURL(url)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
