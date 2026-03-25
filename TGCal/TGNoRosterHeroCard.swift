import SwiftUI

struct TGNoRosterHeroCard: View {
    let action: () -> Void
    var isProcessing: Bool = false

    @State private var glowPulse = false
    @State private var iconBobOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(TGTheme.indigo.opacity(glowPulse ? 0.22 : 0.12))
                        .frame(width: 96, height: 96)
                        .blur(radius: glowPulse ? 0 : 2)

                    Circle()
                        .fill(TGTheme.iconTileFill)
                        .frame(width: 72, height: 72)

                    Image(systemName: "airplane.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(TGTheme.indigo)
                }
                .offset(y: iconBobOffset)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready for takeoff")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(TGTheme.indigo)
                    Text("Welcome to TGCal")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }

            Text("Import your roster PDF to unlock flights, earnings, and calendar tools.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("✈️ Flights  •  💸 Earnings  •  🗓 Calendar")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Button(action: action) {
                if isProcessing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Reading your schedule...")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Import roster PDF")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(TGTheme.indigo)
            .controlSize(.large)
            .disabled(isProcessing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(TGTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(TGTheme.cardStroke, lineWidth: 1.2)
                )
                .shadow(color: TGTheme.cardShadow, radius: 24, x: 0, y: 14)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowPulse = true
                iconBobOffset = -3
            }
        }
    }
}
