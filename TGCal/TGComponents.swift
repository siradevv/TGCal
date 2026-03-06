import SwiftUI
import UIKit

enum TGTheme {
    static let indigo = Color(red: 0.42, green: 0.50, blue: 0.90)
    static let rose = Color(red: 0.94, green: 0.60, blue: 0.76)
    static let mint = Color(red: 0.64, green: 0.89, blue: 0.82)

    static let backgroundGradient = LinearGradient(
        colors: [
            dynamicColor(
                light: UIColor(red: 0.92, green: 0.94, blue: 1.0, alpha: 1),
                dark: UIColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1)
            ),
            dynamicColor(
                light: UIColor(red: 0.90, green: 0.97, blue: 0.98, alpha: 1),
                dark: UIColor(red: 0.08, green: 0.14, blue: 0.18, alpha: 1)
            ),
            dynamicColor(
                light: UIColor(red: 0.96, green: 0.91, blue: 0.98, alpha: 1),
                dark: UIColor(red: 0.13, green: 0.08, blue: 0.17, alpha: 1)
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardFill = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.66),
        dark: UIColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 0.82)
    )

    static let cardStroke = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.95),
        dark: UIColor.white.withAlphaComponent(0.18)
    )

    static let cardShadow = dynamicColor(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.black.withAlphaComponent(0.35)
    )

    static let insetFill = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.62),
        dark: UIColor.white.withAlphaComponent(0.10)
    )

    static let insetStroke = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.92),
        dark: UIColor.white.withAlphaComponent(0.22)
    )

    static let controlFill = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.58),
        dark: UIColor.white.withAlphaComponent(0.14)
    )

    static let controlStroke = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.90),
        dark: UIColor.white.withAlphaComponent(0.24)
    )

    static let iconTileFill = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.88),
        dark: UIColor.white.withAlphaComponent(0.18)
    )

    static let splashIconShadow = dynamicColor(
        light: UIColor.black.withAlphaComponent(0.14),
        dark: UIColor.black.withAlphaComponent(0.42)
    )

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
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
                    .fill(TGTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(TGTheme.cardStroke, lineWidth: 1.1)
                    )
                    .shadow(color: TGTheme.cardShadow, radius: 20, x: 0, y: 12)
            )
    }
}

extension View {
    func tgFrostedCard(cornerRadius: CGFloat = 18, verticalPadding: CGFloat = 14) -> some View {
        modifier(TGFrostedCardModifier(cornerRadius: cornerRadius, verticalPadding: verticalPadding))
    }
}
