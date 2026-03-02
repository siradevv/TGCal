import SwiftUI

struct EarningsView: View {
    @EnvironmentObject private var store: TGCalStore

    @State private var selectedSeason: PPBSeason = .summer
    @State private var rateTables: [PPBSeason: PPBRateTable] = [:]
    @State private var loadErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Earnings")
                                        .font(.largeTitle.weight(.semibold))

                                    Text(store.activeMonth == nil ? "No roster loaded" : activeMonthTitle)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(store.activeMonth == nil ? .secondary : .primary)
                                }

                                Spacer()

                                Image(systemName: "chart.bar.fill")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(themeIndigo)
                                    .padding(10)
                                    .background(
                                        Circle()
                                            .fill(themeIndigo.opacity(0.14))
                                    )
                            }

                            Picker("Season", selection: $selectedSeason) {
                                ForEach(PPBSeason.allCases) { season in
                                    Text(season.displayName).tag(season)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .tgEarningsCard()
                        .padding(.vertical, 2)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    if let loadErrorMessage {
                        Section {
                            Text(loadErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .tgEarningsCard(cornerRadius: 14, verticalPadding: 12)
                                .padding(.vertical, 2)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } footer: {
                            Text("Rates failed to load. Earnings are currently shown as ฿0.")
                                .textCase(nil)
                        }
                    }

                    if let result = earningsResult {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Estimated Total Earnings")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(themeIndigo)
                                Text(formatTHB(result.totalTHB))
                                    .font(.title2.weight(.bold))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tgEarningsCard()
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }

                        Section {
                            if result.lineItems.isEmpty {
                                Text("No numeric flights found for this month.")
                                    .foregroundStyle(.secondary)
                                    .tgEarningsCard(cornerRadius: 14, verticalPadding: 12)
                                    .padding(.vertical, 2)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } else {
                                ForEach(result.lineItems) { item in
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("TG \(item.flightNumber)")
                                                .font(.headline.weight(.semibold))
                                            Text("\(item.count) × \(formatTHB(item.ppb ?? 0))")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text(formatTHB(item.subtotal))
                                            .font(.title3.weight(.bold))
                                            .monospacedDigit()
                                    }
                                    .tgEarningsCard(cornerRadius: 16, verticalPadding: 12)
                                    .padding(.vertical, 2)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            }
                        } header: {
                            sectionHeader("Flight Breakdown", systemImage: "airplane.departure")
                        }

                        if result.missingFlights.isEmpty == false {
                            Section {
                                ForEach(missingRows(from: result.missingFlights), id: \.flight) { row in
                                    HStack {
                                        Text("TG \(row.flight)")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text("x\(row.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .tgEarningsCard(cornerRadius: 14, verticalPadding: 12)
                                    .padding(.vertical, 2)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            } header: {
                                sectionHeader("Missing PPB", systemImage: "exclamationmark.triangle")
                            } footer: {
                                Text("These flights were counted as ฿0.")
                                    .textCase(nil)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .tint(themeIndigo)
            }
            .task {
                loadRateTablesIfNeeded()
            }
        }
    }

    private var earningsResult: MonthEarningsResult? {
        guard let month = store.activeMonth else {
            return nil
        }

        return EarningsCalculator.calculate(
            for: month,
            season: selectedSeason,
            tables: rateTables
        )
    }

    private var activeMonthTitle: String {
        guard let active = store.activeMonth else {
            return "No roster loaded"
        }

        var components = DateComponents()
        components.calendar = .roster
        components.timeZone = rosterTimeZone
        components.year = active.year
        components.month = active.month
        components.day = 1

        let date = components.date ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func loadRateTablesIfNeeded() {
        guard rateTables.isEmpty, loadErrorMessage == nil else { return }

        do {
            rateTables = try EarningsCalculator.loadRateTables()
        } catch {
            loadErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func formatTHB(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "฿\(number)"
    }

    private func missingRows(from missing: [String: Int]) -> [(flight: String, count: Int)] {
        missing
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                let left = Int(lhs.0) ?? .max
                let right = Int(rhs.0) ?? .max
                if left != right { return left < right }
                return lhs.0 < rhs.0
            }
    }

    private var themeIndigo: Color {
        Color(red: 0.42, green: 0.50, blue: 0.90)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.92, green: 0.94, blue: 1.0),
                Color(red: 0.90, green: 0.97, blue: 0.98),
                Color(red: 0.96, green: 0.91, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(themeIndigo)
            .textCase(nil)
    }
}

private struct EarningsCardModifier: ViewModifier {
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

private extension View {
    func tgEarningsCard(cornerRadius: CGFloat = 18, verticalPadding: CGFloat = 14) -> some View {
        modifier(EarningsCardModifier(cornerRadius: cornerRadius, verticalPadding: verticalPadding))
    }
}
