import SwiftUI

/// Track positioning flights, commute expenses, and total time away from home.
struct CommuteTrackerView: View {
    @ObservedObject private var commuteStore = CommuteStore.shared
    @State private var isShowingAddSheet = false
    @State private var editingRecord: CommuteRecord?

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Summary card
                    summaryCard

                    // Records list
                    if commuteStore.records.isEmpty {
                        emptyState
                    } else {
                        TGSectionHeader(title: "History", systemImage: "clock.arrow.circlepath")
                            .padding(.top, 4)

                        ForEach(commuteStore.records) { record in
                            commuteRow(record)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Commute Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(TGTheme.indigo)
                }
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddCommuteRecordView()
        }
        .sheet(item: $editingRecord) { record in
            AddCommuteRecordView(editing: record)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TGSectionHeader(title: "Summary", systemImage: "chart.bar.fill")

            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(commuteStore.totalTrips)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(TGTheme.indigo)
                    Text("Trips")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text(formatDuration(commuteStore.totalMinutes))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(TGTheme.indigo)
                    Text("Travel Time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text(formatCost(commuteStore.totalCostTHB))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(TGTheme.indigo)
                    Text("THB")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .tgFrostedCard(cornerRadius: 16, verticalPadding: 14)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "car.side")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No commutes tracked")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Track your trips to and from base to see total costs and travel time.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                isShowingAddSheet = true
            } label: {
                Label("Add Commute", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(TGTheme.indigo)
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Row

    private func commuteRow(_ record: CommuteRecord) -> some View {
        Button {
            editingRecord = record
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(TGTheme.indigo.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: record.mode.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TGTheme.indigo)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(record.fromCity) → \(record.toCity)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(dateText(record.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(record.costText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text(formatDuration(record.durationMinutes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TGTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(TGTheme.cardStroke, lineWidth: 1)
                    )
                    .shadow(color: TGTheme.cardShadow, radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                commuteStore.delete(record.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func formatCost(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Add / Edit Commute Record

struct AddCommuteRecordView: View {
    var editing: CommuteRecord?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var commuteStore = CommuteStore.shared

    @State private var date = Date()
    @State private var fromCity = ""
    @State private var toCity = ""
    @State private var mode: CommuteMode = .taxi
    @State private var hours = 0
    @State private var minutes = 30
    @State private var cost = ""
    @State private var currency = "THB"
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .tint(TGTheme.indigo)

                        formField("From", text: $fromCity, placeholder: "e.g. Chiang Mai")
                        formField("To", text: $toCity, placeholder: "e.g. Bangkok")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mode")
                                .font(.subheadline.weight(.semibold))
                            Picker("Mode", selection: $mode) {
                                ForEach(CommuteMode.allCases) { m in
                                    Label(m.displayName, systemImage: m.icon).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Duration")
                                    .font(.subheadline.weight(.semibold))
                                HStack {
                                    Picker("Hours", selection: $hours) {
                                        ForEach(0..<24, id: \.self) { Text("\($0)h") }
                                    }
                                    .pickerStyle(.menu)
                                    Picker("Minutes", selection: $minutes) {
                                        ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { Text("\($0)m") }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            formField("Cost", text: $cost, placeholder: "0")
                                .keyboardType(.decimalPad)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Currency")
                                    .font(.subheadline.weight(.semibold))
                                Picker("Currency", selection: $currency) {
                                    Text("THB").tag("THB")
                                    Text("USD").tag("USD")
                                    Text("EUR").tag("EUR")
                                    Text("GBP").tag("GBP")
                                    Text("JPY").tag("JPY")
                                }
                                .pickerStyle(.menu)
                                .tint(TGTheme.indigo)
                            }
                        }

                        formField("Note (optional)", text: $note, placeholder: "")

                        Button {
                            saveRecord()
                        } label: {
                            Text(editing != nil ? "Update" : "Add Commute")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TGTheme.indigo)
                        .disabled(fromCity.isEmpty || toCity.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(editing != nil ? "Edit Commute" : "Add Commute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let record = editing {
                    date = record.date
                    fromCity = record.fromCity
                    toCity = record.toCity
                    mode = record.mode
                    hours = record.durationMinutes / 60
                    minutes = record.durationMinutes % 60
                    cost = String(Int(record.cost))
                    currency = record.currency
                    note = record.note ?? ""
                }
            }
        }
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TGTheme.insetFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(TGTheme.insetStroke, lineWidth: 1)
                        )
                )
        }
    }

    private func saveRecord() {
        let record = CommuteRecord(
            id: editing?.id ?? UUID(),
            date: date,
            fromCity: fromCity,
            toCity: toCity,
            mode: mode,
            durationMinutes: hours * 60 + minutes,
            cost: Double(cost) ?? 0,
            currency: currency,
            note: note.isEmpty ? nil : note
        )

        if editing != nil {
            commuteStore.update(record)
        } else {
            commuteStore.add(record)
        }
        dismiss()
    }
}
