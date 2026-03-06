import SwiftUI

enum TGTheme {
    static let indigo = Color(red: 0.42, green: 0.50, blue: 0.90)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.92, green: 0.94, blue: 1.0),
            Color(red: 0.90, green: 0.97, blue: 0.98),
            Color(red: 0.96, green: 0.91, blue: 0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct TGBackgroundView: View {
    var body: some View {
        TGTheme.backgroundGradient
            .ignoresSafeArea()
    }
}

struct TGSectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.headline.weight(.semibold))
        .foregroundStyle(TGTheme.indigo)
    }
}

private struct TGFrostedCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.66))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.95), lineWidth: 1.1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 12)
            )
    }
}

extension View {
    func tgFrostedCard(cornerRadius: CGFloat = 18, verticalPadding: CGFloat = 14) -> some View {
        modifier(TGFrostedCardModifier(cornerRadius: cornerRadius, verticalPadding: verticalPadding))
    }
}
