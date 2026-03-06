import SwiftUI

struct EarningsView: View {
    @EnvironmentObject private var store: TGCalStore

    @State private var selectedSeason: PPBSeason = .summer
    @State private var rateTables: [PPBSeason: PPBRateTable] = [:]
    @State private var loadErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Earnings")
                                    .font(.largeTitle.weight(.semibold))

                                Text(store.activeMonth == nil ? "No roster loaded" : activeMonthTitle)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(store.activeMonth == nil ? .secondary : .primary)
                            }

                            Picker("Season", selection: $selectedSeason) {
                                ForEach(PPBSeason.allCases) { season in
                                    Text(season.displayName).tag(season)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .tgEarningsCard(cornerRadius: 20, verticalPadding: 16)
                        .padding(.vertical, 0)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    if let loadErrorMessage {
                        Section {
                            Text(loadErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .tgEarningsCard(cornerRadius: 14, verticalPadding: 12)
                                .padding(.vertical, 0)
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
                                TGSectionHeader(title: "Estimated Total Earnings")
                                Text(formatTHB(result.totalTHB))
                                    .font(.title2.weight(.bold))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tgEarningsCard()
                            .padding(.vertical, 0)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }

                        Section {
                            if result.lineItems.isEmpty {
                                Text("No numeric flights found for this month.")
                                    .foregroundStyle(.secondary)
                                    .tgEarningsCard(cornerRadius: 14, verticalPadding: 12)
                                    .padding(.vertical, 0)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(result.lineItems.indices, id: \.self) { index in
                                        let item = result.lineItems[index]

                                        HStack(spacing: 12) {
                                            Text("TG \(item.flightNumber)")
                                                .font(.headline.weight(.semibold))

                                            Spacer()

                                            Text(formatTHB(item.subtotal))
                                                .font(.headline.weight(.semibold))
                                                .monospacedDigit()
                                        }
                                        .padding(.vertical, 10)

                                        if index < result.lineItems.count - 1 {
                                            Divider()
                                        }
                                    }
                                }
                                .tgEarningsCard(cornerRadius: 14, verticalPadding: 6)
                                .padding(.vertical, 0)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            TGSectionHeader(title: "Flight Breakdown", systemImage: "airplane.departure")
                                .textCase(nil)
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
                                    .tgEarningsCard(cornerRadius: 14, verticalPadding: 10)
                                    .padding(.vertical, 0)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            } header: {
                                TGSectionHeader(title: "Missing PPB", systemImage: "exclamationmark.triangle")
                                    .textCase(nil)
                            } footer: {
                                Text("These flights were counted as ฿0.")
                                    .textCase(nil)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .tint(TGTheme.indigo)
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
                    .fill(TGTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(TGTheme.cardStroke, lineWidth: 1.1)
                    )
                    .shadow(color: TGTheme.cardShadow, radius: 14, x: 0, y: 8)
            )
    }
}

private extension View {
    func tgEarningsCard(cornerRadius: CGFloat = 18, verticalPadding: CGFloat = 14) -> some View {
        modifier(EarningsCardModifier(cornerRadius: cornerRadius, verticalPadding: verticalPadding))
    }
}
