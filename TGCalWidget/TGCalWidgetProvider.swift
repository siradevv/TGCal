import WidgetKit
import Foundation

struct TGCalWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> NextFlightEntry {
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

    func getSnapshot(in context: Context, completion: @escaping (NextFlightEntry) -> Void) {
        let entry = loadEntry() ?? placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFlightEntry>) -> Void) {
        let entry = loadEntry() ?? NextFlightEntry(date: Date(), flight: nil)

        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    // MARK: - Shared Data

    private func loadEntry() -> NextFlightEntry? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tgcal.shared"
        ) else {
            return nil
        }

        let fileURL = containerURL.appendingPathComponent("next_flight.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let snapshot = try decoder.decode(NextFlightSnapshot.self, from: data)

            // Only show future flights
            guard snapshot.departureDate > Date() else {
                return NextFlightEntry(date: Date(), flight: nil)
            }

            return NextFlightEntry(date: Date(), flight: snapshot)
        } catch {
            return nil
        }
    }
}
