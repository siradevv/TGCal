import WidgetKit
import SwiftUI

@main
struct TGCalWidget: Widget {
    let kind = "TGCalNextFlightWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TGCalWidgetProvider()
        ) { entry in
            TGCalWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Flight")
        .description("See your next upcoming flight at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TGCalWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextFlightEntry

    var body: some View {
        Group {
            if let flight = entry.flight {
                switch family {
                case .systemMedium:
                    MediumWidgetView(flight: flight)
                default:
                    SmallWidgetView(flight: flight)
                }
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "airplane")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No upcoming flights")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var widgetBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.92, green: 0.94, blue: 1.0),
                Color(red: 0.90, green: 0.97, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let flight: NextFlightSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "airplane.departure")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.90))
                Text(flight.flightCode)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.90))
            }

            Text(flight.routeText)
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(flight.departureTimeText)
                .font(.title2.weight(.bold))
                .monospacedDigit()

            Text(flight.relativeDateText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let flight: NextFlightSnapshot

    var body: some View {
        HStack(spacing: 16) {
            // Left side — flight info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "airplane.departure")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.90))
                    Text(flight.flightCode)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.90))
                }

                Text(flight.routeText)
                    .font(.title3.weight(.semibold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text(flight.flagEmoji)
                        .font(.subheadline)
                    Text(flight.destinationCity)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Right side — time
            VStack(alignment: .trailing, spacing: 4) {
                Text(flight.relativeDateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("DEP")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(flight.departureTimeText)
                    .font(.title.weight(.bold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Small", as: .systemSmall) {
    TGCalWidget()
} timeline: {
    NextFlightEntry(
        date: Date(),
        flight: NextFlightSnapshot(
            flightCode: "TG 971",
            originCode: "BKK",
            destinationCode: "NRT",
            departureTime: "14:30",
            departureDate: Date().addingTimeInterval(86400),
            destinationCity: "Tokyo",
            countryCode: "JP"
        )
    )
}

#Preview("Medium", as: .systemMedium) {
    TGCalWidget()
} timeline: {
    NextFlightEntry(
        date: Date(),
        flight: NextFlightSnapshot(
            flightCode: "TG 971",
            originCode: "BKK",
            destinationCode: "NRT",
            departureTime: "14:30",
            departureDate: Date().addingTimeInterval(86400),
            destinationCity: "Tokyo",
            countryCode: "JP"
        )
    )
}

#Preview("Empty", as: .systemSmall) {
    TGCalWidget()
} timeline: {
    NextFlightEntry(date: Date(), flight: nil)
}
