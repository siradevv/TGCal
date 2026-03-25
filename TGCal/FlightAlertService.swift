import Foundation

/// Monitors upcoming flights for delays, gate changes, and disruptions.
@MainActor
final class FlightAlertService: ObservableObject {

    static let shared = FlightAlertService()

    @Published var activeAlerts: [FlightAlert] = []

    private var monitoredFlights: [(flightCode: String, origin: String, destination: String, serviceDate: Date, departureDate: Date)] = []
    private var monitorTask: Task<Void, Never>?

    private init() {}

    // MARK: - Monitoring

    /// Begins polling for disruptions on upcoming flights.
    func startMonitoring(flights: [(flightCode: String, origin: String, destination: String, serviceDate: Date, departureDate: Date)]) {
        monitoredFlights = flights
        monitorTask?.cancel()

        monitorTask = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.checkForDisruptions()
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 minutes
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Manually trigger a check for all monitored flights.
    func refreshAlerts() async {
        await checkForDisruptions()
    }

    // MARK: - Disruption Check

    private func checkForDisruptions() async {
        var newAlerts: [FlightAlert] = []

        for flight in monitoredFlights {
            // Only check flights departing in the next 48 hours
            let hoursUntilDeparture = flight.departureDate.timeIntervalSinceNow / 3600
            guard hoursUntilDeparture > 0 && hoursUntilDeparture < 48 else { continue }

            do {
                let details = try await AviationstackService.shared.nextFlightDetails(
                    flightCode: flight.flightCode,
                    originCode: flight.origin,
                    destinationCode: flight.destination,
                    serviceDate: flight.serviceDate,
                    expectedDepartureDate: flight.departureDate
                )

                // Check for gate changes
                if let gate = details?.departureGate,
                   gate.isEmpty == false,
                   alertIsNew(flightCode: flight.flightCode, type: .gateChange) {
                    newAlerts.append(FlightAlert(
                        id: UUID(),
                        flightCode: flight.flightCode,
                        alertType: .gateChange,
                        message: "\(flight.flightCode): \(gate)",
                        timestamp: Date()
                    ))
                }
            } catch {
                // Silent failure — will retry on next poll
            }
        }

        if newAlerts.isEmpty == false {
            activeAlerts.append(contentsOf: newAlerts)

            // Send push notifications for new alerts
            for alert in newAlerts {
                NotificationService.shared.scheduleFlightAlert(alert)
            }
        }

        // Prune old alerts (older than 24 hours)
        activeAlerts.removeAll { Date().timeIntervalSince($0.timestamp) > 24 * 3600 }
    }

    private func alertIsNew(flightCode: String, type: FlightAlertType) -> Bool {
        activeAlerts.contains { $0.flightCode == flightCode && $0.alertType == type } == false
    }

    /// Dismiss a specific alert.
    func dismiss(_ alertId: UUID) {
        activeAlerts.removeAll { $0.id == alertId }
    }

    func dismissAll() {
        activeAlerts.removeAll()
    }
}
