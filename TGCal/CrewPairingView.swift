import SwiftUI

/// Shows which other crew members in the app are on the same upcoming flights.
struct CrewPairingView: View {
    @EnvironmentObject private var store: TGCalStore
    @ObservedObject private var pairingService = CrewPairingService.shared
    @ObservedObject private var supabase = SupabaseService.shared

    @AppStorage("crew_pairing_enabled") private var isPairingEnabled = true

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Opt-in toggle
                    optInCard

                    if isPairingEnabled {
                        // Upcoming flights with pairing info
                        if upcomingFlights.isEmpty {
                            emptyState
                        } else {
                            ForEach(upcomingFlights, id: \.flightCode) { flight in
                                flightPairingCard(flight)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Crew Pairing")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isPairingEnabled, let first = upcomingFlights.first {
                await pairingService.findCrewOnFlight(
                    flightCode: first.flightCode,
                    flightDate: first.flightDate
                )
            }
        }
    }

    // MARK: - Opt-in Card

    private var optInCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isPairingEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show me on flights")
                        .font(.subheadline.weight(.semibold))
                    Text("Let other crew see you're on the same flight")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(TGTheme.indigo)
            .onChange(of: isPairingEnabled) { _, enabled in
                if enabled == false {
                    Task { await pairingService.deregisterAllFlights() }
                } else if let month = store.activeMonth {
                    Task { await pairingService.registerFlights(from: month) }
                }
            }
        }
        .tgFrostedCard(cornerRadius: 16, verticalPadding: 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No upcoming flights")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Import your roster to see who's flying with you.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Flight Pairing Card

    private func flightPairingCard(_ flight: UpcomingFlight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(flight.flightCode)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TGTheme.indigo)

                Spacer()

                Text(flight.flightDate)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(flight.route)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            if pairingService.isLoading {
                HStack {
                    ProgressView().tint(TGTheme.indigo)
                    Text("Looking for crew...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                let pairings = pairingService.pairingsForNextFlight.filter {
                    $0.flightCode == flight.flightCode && $0.flightDate == flight.flightDate
                }

                if pairings.isEmpty {
                    Text("No other crew members found on this flight yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pairings) { pairing in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(TGTheme.indigo.opacity(0.12))
                                    .frame(width: 30, height: 30)
                                Text(String(pairing.displayName.prefix(1)).uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(TGTheme.indigo)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pairing.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(pairing.crewRank.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .tgFrostedCard(cornerRadius: 16, verticalPadding: 12)
        .task {
            await pairingService.findCrewOnFlight(
                flightCode: flight.flightCode,
                flightDate: flight.flightDate
            )
        }
    }

    // MARK: - Data

    private struct UpcomingFlight: Equatable {
        let flightCode: String
        let flightDate: String
        let route: String
    }

    private var upcomingFlights: [UpcomingFlight] {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = rosterTimeZone

        var flights: [(UpcomingFlight, Date)] = []

        for month in store.months {
            for (day, keys) in month.flightsByDay {
                for key in keys where key.isAlphabeticDutyCode == false {
                    var comps = DateComponents()
                    comps.calendar = .roster
                    comps.timeZone = rosterTimeZone
                    comps.year = month.year
                    comps.month = month.month
                    comps.day = day

                    guard let date = comps.date, date > now else { continue }

                    let number = key.strippingLeadingZeros()
                    let flightCode = "TG\(number.isEmpty ? "0" : number)"
                    let detail = month.detailsByFlight[key] ?? month.detailsByFlight[key.strippingLeadingZeros()]
                    let route = "\(detail?.origin ?? "BKK") → \(detail?.destination ?? "???")"

                    flights.append((
                        UpcomingFlight(
                            flightCode: flightCode,
                            flightDate: dateFormatter.string(from: date),
                            route: route
                        ),
                        date
                    ))
                }
            }
        }

        return flights
            .sorted { $0.1 < $1.1 }
            .prefix(10)
            .map(\.0)
    }
}
