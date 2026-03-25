import Foundation

struct DestinationWeather: Equatable {
    let temperatureCelsius: Int
    let condition: Condition
    let precipitationChancePercent: Int?
    let windSpeedKph: Int?
    let humidityPercent: Int?

    enum Condition: String, Equatable {
        case rain = "Rain"
        case cloudy = "Cloudy"
        case clear = "Clear"
    }
}

actor WeatherService {
    static let shared = WeatherService()

    private var cachedCurrentWeather: [String: (timestamp: Date, weather: DestinationWeather)] = [:]
    private var cachedArrivalWeather: [String: (timestamp: Date, weather: DestinationWeather)] = [:]

    func currentWeather(latitude: Double, longitude: Double) async throws -> DestinationWeather {
        let key = String(format: "%.3f,%.3f", latitude, longitude)
        if let cached = cachedCurrentWeather[key], Date().timeIntervalSince(cached.timestamp) < 15 * 60 {
            return cached.weather
        }

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code&timezone=auto"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenMeteoCurrentResponse.self, from: data)

        let weather = DestinationWeather(
            temperatureCelsius: Int(decoded.current.temperature2M.rounded()),
            condition: mapCondition(code: decoded.current.weatherCode),
            precipitationChancePercent: nil,
            windSpeedKph: nil,
            humidityPercent: nil
        )

        cachedCurrentWeather[key] = (Date(), weather)
        return weather
    }

    func arrivalWeather(
        latitude: Double,
        longitude: Double,
        arrivalDate: Date,
        timeZoneIdentifier: String
    ) async throws -> DestinationWeather {
        let destinationTimeZone = TimeZone(identifier: timeZoneIdentifier) ?? rosterTimeZone
        let cacheKey = arrivalCacheKey(
            latitude: latitude,
            longitude: longitude,
            arrivalDate: arrivalDate,
            timeZone: destinationTimeZone
        )
        if let cached = cachedArrivalWeather[cacheKey], Date().timeIntervalSince(cached.timestamp) < 30 * 60 {
            return cached.weather
        }

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&hourly=temperature_2m,weather_code,precipitation_probability,wind_speed_10m,relative_humidity_2m&timezone=auto&forecast_days=16"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenMeteoHourlyResponse.self, from: data)
        let weather = try closestHourlyWeather(
            from: decoded.hourly,
            arrivalDate: arrivalDate,
            timeZone: destinationTimeZone
        )

        cachedArrivalWeather[cacheKey] = (Date(), weather)
        return weather
    }

    private func closestHourlyWeather(
        from hourly: OpenMeteoHourlyResponse.Hourly,
        arrivalDate: Date,
        timeZone: TimeZone
    ) throws -> DestinationWeather {
        let count = min(hourly.time.count, min(hourly.temperature2M.count, hourly.weatherCode.count))
        guard count > 0 else {
            throw URLError(.cannotParseResponse)
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var bestIndex: Int?
        var smallestDelta: TimeInterval = .greatestFiniteMagnitude

        for index in 0..<count {
            guard let timestamp = formatter.date(from: hourly.time[index]) else { continue }
            let delta = abs(timestamp.timeIntervalSince(arrivalDate))
            if delta < smallestDelta {
                smallestDelta = delta
                bestIndex = index
            }
        }

        guard let bestIndex else {
            throw URLError(.cannotParseResponse)
        }

        return DestinationWeather(
            temperatureCelsius: Int(hourly.temperature2M[bestIndex].rounded()),
            condition: mapCondition(code: hourly.weatherCode[bestIndex]),
            precipitationChancePercent: optionalRoundedValue(hourly.precipitationProbability, index: bestIndex),
            windSpeedKph: optionalRoundedValue(hourly.windSpeed10M, index: bestIndex),
            humidityPercent: optionalRoundedValue(hourly.relativeHumidity2M, index: bestIndex)
        )
    }

    private func optionalRoundedValue(_ values: [Double]?, index: Int) -> Int? {
        guard let values, values.indices.contains(index) else {
            return nil
        }
        return Int(values[index].rounded())
    }

    private func arrivalCacheKey(
        latitude: Double,
        longitude: Double,
        arrivalDate: Date,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HH"
        let arrivalHour = formatter.string(from: arrivalDate)
        return String(format: "%.3f,%.3f|%@", latitude, longitude, arrivalHour)
    }

    private func mapCondition(code: Int) -> DestinationWeather.Condition {
        switch code {
        case 0:
            return .clear
        case 51...67, 80...82, 95...99:
            return .rain
        default:
            return .cloudy
        }
    }
}

private struct OpenMeteoCurrentResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let temperature2M: Double
        let weatherCode: Int

        private enum CodingKeys: String, CodingKey {
            case temperature2M = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }
}

private struct OpenMeteoHourlyResponse: Decodable {
    let hourly: Hourly

    struct Hourly: Decodable {
        let time: [String]
        let temperature2M: [Double]
        let weatherCode: [Int]
        let precipitationProbability: [Double]?
        let windSpeed10M: [Double]?
        let relativeHumidity2M: [Double]?

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature2M = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitationProbability = "precipitation_probability"
            case windSpeed10M = "wind_speed_10m"
            case relativeHumidity2M = "relative_humidity_2m"
        }
    }
}
