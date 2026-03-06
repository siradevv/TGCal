import Foundation

struct DestinationInfo: Equatable {
    let airportCode: String
    let cityName: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
    let currencyCode: String
    let plugType: PlugType
    let voltage: Int
}

enum PlugType: String, CaseIterable {
    case A
    case C
    case F
    case G
    case I

    var displayLabel: String {
        "Type \(rawValue)"
    }

    var assetName: String {
        "PlugType\(rawValue)"
    }
}

enum DestinationMetadata {
    static func info(for airportCode: String) -> DestinationInfo {
        let code = airportCode.uppercased()

        if let airportSeed = airportSeeds[code],
           let countryProfile = countryProfiles[airportSeed.countryCode] {
            return DestinationInfo(
                airportCode: code,
                cityName: airportSeed.cityName,
                countryCode: airportSeed.countryCode,
                latitude: airportSeed.latitude,
                longitude: airportSeed.longitude,
                timeZoneIdentifier: airportSeed.timeZoneIdentifier,
                currencyCode: countryProfile.currencyCode,
                plugType: countryProfile.plugType,
                voltage: countryProfile.voltage
            )
        }

        return fallbackInfo(for: code)
    }

    private static func fallbackInfo(for airportCode: String) -> DestinationInfo {
        let fallbackCountry = "TH"
        let profile = countryProfiles[fallbackCountry] ?? CountryProfile(currencyCode: "THB", plugType: .C, voltage: 220)

        return DestinationInfo(
            airportCode: airportCode,
            cityName: airportCode,
            countryCode: fallbackCountry,
            latitude: 13.6900,
            longitude: 100.7501,
            timeZoneIdentifier: "Asia/Bangkok",
            currencyCode: profile.currencyCode,
            plugType: profile.plugType,
            voltage: profile.voltage
        )
    }

    private struct AirportSeed {
        let cityName: String
        let countryCode: String
        let latitude: Double
        let longitude: Double
        let timeZoneIdentifier: String
    }

    private struct CountryProfile {
        let currencyCode: String
        let plugType: PlugType
        let voltage: Int
    }

    private static let countryProfiles: [String: CountryProfile] = [
        "AE": CountryProfile(currencyCode: "AED", plugType: .G, voltage: 230),
        "AT": CountryProfile(currencyCode: "EUR", plugType: .F, voltage: 230),
        "AU": CountryProfile(currencyCode: "AUD", plugType: .I, voltage: 230),
        "BD": CountryProfile(currencyCode: "BDT", plugType: .G, voltage: 220),
        "BE": CountryProfile(currencyCode: "EUR", plugType: .F, voltage: 230),
        "CA": CountryProfile(currencyCode: "CAD", plugType: .A, voltage: 120),
        "CH": CountryProfile(currencyCode: "CHF", plugType: .C, voltage: 230),
        "CN": CountryProfile(currencyCode: "CNY", plugType: .I, voltage: 220),
        "DE": CountryProfile(currencyCode: "EUR", plugType: .F, voltage: 230),
        "DK": CountryProfile(currencyCode: "DKK", plugType: .F, voltage: 230),
        "EG": CountryProfile(currencyCode: "EGP", plugType: .C, voltage: 220),
        "ES": CountryProfile(currencyCode: "EUR", plugType: .F, voltage: 230),
        "FI": CountryProfile(currencyCode: "EUR", plugType: .F, voltage: 230),
        "FR": CountryProfile(currencyCode: "EUR", plugType: .F, voltage: 230),
        "GB": CountryProfile(currencyCode: "GBP", plugType: .G, voltage: 230),
        "GR": CountryProfile(currencyCode: "EUR", plugType: .F, voltage: 230),
        "HK": CountryProfile(currencyCode: "HKD", plugType: .G, voltage: 220),
        "ID": CountryProfile(currencyCode: "IDR", plugType: .C, voltage: 230),
        "IN": CountryProfile(currencyCode: "INR", plugType: .C, voltage: 230),
        "IT": CountryProfile(currencyCode: "EUR", plugType: .F, voltage: 230),
        "JP": CountryProfile(currencyCode: "JPY", plugType: .A, voltage: 100),
        "KH": CountryProfile(currencyCode: "KHR", plugType: .C, voltage: 230),
        "KR": CountryProfile(currencyCode: "KRW", plugType: .C, voltage: 220),
        "KW": CountryProfile(currencyCode: "KWD", plugType: .G, voltage: 240),
        "LA": CountryProfile(currencyCode: "LAK", plugType: .C, voltage: 230),
        "LK": CountryProfile(currencyCode: "LKR", plugType: .G, voltage: 230),
        "MM": CountryProfile(currencyCode: "MMK", plugType: .C, voltage: 230),
        "MO": CountryProfile(currencyCode: "MOP", plugType: .G, voltage: 220),
        "MY": CountryProfile(currencyCode: "MYR", plugType: .G, voltage: 240),
        "NL": CountryProfile(currencyCode: "EUR", plugType: .F, voltage: 230),
        "NO": CountryProfile(currencyCode: "NOK", plugType: .F, voltage: 230),
        "NP": CountryProfile(currencyCode: "NPR", plugType: .C, voltage: 230),
        "NZ": CountryProfile(currencyCode: "NZD", plugType: .I, voltage: 230),
        "PH": CountryProfile(currencyCode: "PHP", plugType: .A, voltage: 220),
        "QA": CountryProfile(currencyCode: "QAR", plugType: .G, voltage: 240),
        "SA": CountryProfile(currencyCode: "SAR", plugType: .G, voltage: 220),
        "SE": CountryProfile(currencyCode: "SEK", plugType: .F, voltage: 230),
        "SG": CountryProfile(currencyCode: "SGD", plugType: .G, voltage: 230),
        "TH": CountryProfile(currencyCode: "THB", plugType: .C, voltage: 220),
        "TR": CountryProfile(currencyCode: "TRY", plugType: .F, voltage: 230),
        "TW": CountryProfile(currencyCode: "TWD", plugType: .A, voltage: 110),
        "US": CountryProfile(currencyCode: "USD", plugType: .A, voltage: 120),
        "VN": CountryProfile(currencyCode: "VND", plugType: .A, voltage: 220),
        "ZA": CountryProfile(currencyCode: "ZAR", plugType: .C, voltage: 230)
    ]

    private static let airportSeeds: [String: AirportSeed] = [
        "AKL": AirportSeed(cityName: "Auckland", countryCode: "NZ", latitude: -36.9980, longitude: 174.7920, timeZoneIdentifier: "Pacific/Auckland"),
        "AMS": AirportSeed(cityName: "Amsterdam", countryCode: "NL", latitude: 52.3100, longitude: 4.7683, timeZoneIdentifier: "Europe/Amsterdam"),
        "ARN": AirportSeed(cityName: "Stockholm", countryCode: "SE", latitude: 59.6519, longitude: 17.9186, timeZoneIdentifier: "Europe/Stockholm"),
        "ATH": AirportSeed(cityName: "Athens", countryCode: "GR", latitude: 37.9364, longitude: 23.9445, timeZoneIdentifier: "Europe/Athens"),
        "AUH": AirportSeed(cityName: "Abu Dhabi", countryCode: "AE", latitude: 24.4330, longitude: 54.6511, timeZoneIdentifier: "Asia/Dubai"),
        "BCN": AirportSeed(cityName: "Barcelona", countryCode: "ES", latitude: 41.2974, longitude: 2.0833, timeZoneIdentifier: "Europe/Madrid"),
        "BKK": AirportSeed(cityName: "Bangkok", countryCode: "TH", latitude: 13.6900, longitude: 100.7501, timeZoneIdentifier: "Asia/Bangkok"),
        "BLR": AirportSeed(cityName: "Bengaluru", countryCode: "IN", latitude: 13.1989, longitude: 77.7063, timeZoneIdentifier: "Asia/Kolkata"),
        "BNE": AirportSeed(cityName: "Brisbane", countryCode: "AU", latitude: -27.3842, longitude: 153.1175, timeZoneIdentifier: "Australia/Brisbane"),
        "BOM": AirportSeed(cityName: "Mumbai", countryCode: "IN", latitude: 19.0896, longitude: 72.8656, timeZoneIdentifier: "Asia/Kolkata"),
        "BOS": AirportSeed(cityName: "Boston", countryCode: "US", latitude: 42.3656, longitude: -71.0096, timeZoneIdentifier: "America/New_York"),
        "BRU": AirportSeed(cityName: "Brussels", countryCode: "BE", latitude: 50.9010, longitude: 4.4844, timeZoneIdentifier: "Europe/Brussels"),
        "CAI": AirportSeed(cityName: "Cairo", countryCode: "EG", latitude: 30.1120, longitude: 31.4000, timeZoneIdentifier: "Africa/Cairo"),
        "CAN": AirportSeed(cityName: "Guangzhou", countryCode: "CN", latitude: 23.3924, longitude: 113.2988, timeZoneIdentifier: "Asia/Shanghai"),
        "CCU": AirportSeed(cityName: "Kolkata", countryCode: "IN", latitude: 22.6547, longitude: 88.4467, timeZoneIdentifier: "Asia/Kolkata"),
        "CDG": AirportSeed(cityName: "Paris", countryCode: "FR", latitude: 49.0097, longitude: 2.5479, timeZoneIdentifier: "Europe/Paris"),
        "CGK": AirportSeed(cityName: "Jakarta", countryCode: "ID", latitude: -6.1261, longitude: 106.6560, timeZoneIdentifier: "Asia/Jakarta"),
        "CHC": AirportSeed(cityName: "Christchurch", countryCode: "NZ", latitude: -43.4894, longitude: 172.5322, timeZoneIdentifier: "Pacific/Auckland"),
        "CMB": AirportSeed(cityName: "Colombo", countryCode: "LK", latitude: 7.1808, longitude: 79.8841, timeZoneIdentifier: "Asia/Colombo"),
        "CNX": AirportSeed(cityName: "Chiang Mai", countryCode: "TH", latitude: 18.7668, longitude: 98.9626, timeZoneIdentifier: "Asia/Bangkok"),
        "CPH": AirportSeed(cityName: "Copenhagen", countryCode: "DK", latitude: 55.6180, longitude: 12.6560, timeZoneIdentifier: "Europe/Copenhagen"),
        "CTU": AirportSeed(cityName: "Chengdu", countryCode: "CN", latitude: 30.5785, longitude: 103.9471, timeZoneIdentifier: "Asia/Shanghai"),
        "DAC": AirportSeed(cityName: "Dhaka", countryCode: "BD", latitude: 23.8433, longitude: 90.3978, timeZoneIdentifier: "Asia/Dhaka"),
        "DEL": AirportSeed(cityName: "Delhi", countryCode: "IN", latitude: 28.5562, longitude: 77.1000, timeZoneIdentifier: "Asia/Kolkata"),
        "DFW": AirportSeed(cityName: "Dallas", countryCode: "US", latitude: 32.8998, longitude: -97.0403, timeZoneIdentifier: "America/Chicago"),
        "DPS": AirportSeed(cityName: "Denpasar", countryCode: "ID", latitude: -8.7481, longitude: 115.1670, timeZoneIdentifier: "Asia/Makassar"),
        "DOH": AirportSeed(cityName: "Doha", countryCode: "QA", latitude: 25.2730, longitude: 51.6080, timeZoneIdentifier: "Asia/Qatar"),
        "DXB": AirportSeed(cityName: "Dubai", countryCode: "AE", latitude: 25.2532, longitude: 55.3657, timeZoneIdentifier: "Asia/Dubai"),
        "EWR": AirportSeed(cityName: "Newark", countryCode: "US", latitude: 40.6895, longitude: -74.1745, timeZoneIdentifier: "America/New_York"),
        "FCO": AirportSeed(cityName: "Rome", countryCode: "IT", latitude: 41.8003, longitude: 12.2389, timeZoneIdentifier: "Europe/Rome"),
        "FRA": AirportSeed(cityName: "Frankfurt", countryCode: "DE", latitude: 50.0379, longitude: 8.5622, timeZoneIdentifier: "Europe/Berlin"),
        "FUK": AirportSeed(cityName: "Fukuoka", countryCode: "JP", latitude: 33.5859, longitude: 130.4510, timeZoneIdentifier: "Asia/Tokyo"),
        "HAN": AirportSeed(cityName: "Hanoi", countryCode: "VN", latitude: 21.2211, longitude: 105.8070, timeZoneIdentifier: "Asia/Ho_Chi_Minh"),
        "HEL": AirportSeed(cityName: "Helsinki", countryCode: "FI", latitude: 60.3172, longitude: 24.9633, timeZoneIdentifier: "Europe/Helsinki"),
        "HKG": AirportSeed(cityName: "Hong Kong", countryCode: "HK", latitude: 22.3080, longitude: 113.9185, timeZoneIdentifier: "Asia/Hong_Kong"),
        "HKT": AirportSeed(cityName: "Phuket", countryCode: "TH", latitude: 8.1132, longitude: 98.3168, timeZoneIdentifier: "Asia/Bangkok"),
        "HND": AirportSeed(cityName: "Tokyo", countryCode: "JP", latitude: 35.5494, longitude: 139.7798, timeZoneIdentifier: "Asia/Tokyo"),
        "HYD": AirportSeed(cityName: "Hyderabad", countryCode: "IN", latitude: 17.2403, longitude: 78.4294, timeZoneIdentifier: "Asia/Kolkata"),
        "IAH": AirportSeed(cityName: "Houston", countryCode: "US", latitude: 29.9902, longitude: -95.3368, timeZoneIdentifier: "America/Chicago"),
        "ICN": AirportSeed(cityName: "Seoul", countryCode: "KR", latitude: 37.4602, longitude: 126.4406, timeZoneIdentifier: "Asia/Seoul"),
        "IST": AirportSeed(cityName: "Istanbul", countryCode: "TR", latitude: 41.2753, longitude: 28.7519, timeZoneIdentifier: "Europe/Istanbul"),
        "JED": AirportSeed(cityName: "Jeddah", countryCode: "SA", latitude: 21.6702, longitude: 39.1523, timeZoneIdentifier: "Asia/Riyadh"),
        "JFK": AirportSeed(cityName: "New York", countryCode: "US", latitude: 40.6413, longitude: -73.7781, timeZoneIdentifier: "America/New_York"),
        "JNB": AirportSeed(cityName: "Johannesburg", countryCode: "ZA", latitude: -26.1337, longitude: 28.2420, timeZoneIdentifier: "Africa/Johannesburg"),
        "KBV": AirportSeed(cityName: "Krabi", countryCode: "TH", latitude: 8.0991, longitude: 98.9862, timeZoneIdentifier: "Asia/Bangkok"),
        "KIX": AirportSeed(cityName: "Osaka", countryCode: "JP", latitude: 34.4347, longitude: 135.2442, timeZoneIdentifier: "Asia/Tokyo"),
        "KMG": AirportSeed(cityName: "Kunming", countryCode: "CN", latitude: 25.1019, longitude: 102.9292, timeZoneIdentifier: "Asia/Shanghai"),
        "KNO": AirportSeed(cityName: "Medan", countryCode: "ID", latitude: 3.6422, longitude: 98.8850, timeZoneIdentifier: "Asia/Jakarta"),
        "KTM": AirportSeed(cityName: "Kathmandu", countryCode: "NP", latitude: 27.6966, longitude: 85.3591, timeZoneIdentifier: "Asia/Kathmandu"),
        "KUL": AirportSeed(cityName: "Kuala Lumpur", countryCode: "MY", latitude: 2.7456, longitude: 101.7072, timeZoneIdentifier: "Asia/Kuala_Lumpur"),
        "KWI": AirportSeed(cityName: "Kuwait City", countryCode: "KW", latitude: 29.2265, longitude: 47.9689, timeZoneIdentifier: "Asia/Kuwait"),
        "LAX": AirportSeed(cityName: "Los Angeles", countryCode: "US", latitude: 33.9416, longitude: -118.4085, timeZoneIdentifier: "America/Los_Angeles"),
        "LGW": AirportSeed(cityName: "London", countryCode: "GB", latitude: 51.1537, longitude: -0.1821, timeZoneIdentifier: "Europe/London"),
        "LHR": AirportSeed(cityName: "London", countryCode: "GB", latitude: 51.4700, longitude: -0.4543, timeZoneIdentifier: "Europe/London"),
        "MAA": AirportSeed(cityName: "Chennai", countryCode: "IN", latitude: 12.9900, longitude: 80.1693, timeZoneIdentifier: "Asia/Kolkata"),
        "MAD": AirportSeed(cityName: "Madrid", countryCode: "ES", latitude: 40.4722, longitude: -3.5609, timeZoneIdentifier: "Europe/Madrid"),
        "MAN": AirportSeed(cityName: "Manchester", countryCode: "GB", latitude: 53.3537, longitude: -2.2749, timeZoneIdentifier: "Europe/London"),
        "MEL": AirportSeed(cityName: "Melbourne", countryCode: "AU", latitude: -37.6733, longitude: 144.8430, timeZoneIdentifier: "Australia/Melbourne"),
        "MFM": AirportSeed(cityName: "Macau", countryCode: "MO", latitude: 22.1496, longitude: 113.5910, timeZoneIdentifier: "Asia/Macau"),
        "MIA": AirportSeed(cityName: "Miami", countryCode: "US", latitude: 25.7959, longitude: -80.2870, timeZoneIdentifier: "America/New_York"),
        "MNL": AirportSeed(cityName: "Manila", countryCode: "PH", latitude: 14.5086, longitude: 121.0198, timeZoneIdentifier: "Asia/Manila"),
        "MUC": AirportSeed(cityName: "Munich", countryCode: "DE", latitude: 48.3538, longitude: 11.7861, timeZoneIdentifier: "Europe/Berlin"),
        "MXP": AirportSeed(cityName: "Milan", countryCode: "IT", latitude: 45.6306, longitude: 8.7281, timeZoneIdentifier: "Europe/Rome"),
        "NGO": AirportSeed(cityName: "Nagoya", countryCode: "JP", latitude: 34.8584, longitude: 136.8053, timeZoneIdentifier: "Asia/Tokyo"),
        "NRT": AirportSeed(cityName: "Tokyo", countryCode: "JP", latitude: 35.7719, longitude: 140.3928, timeZoneIdentifier: "Asia/Tokyo"),
        "ORD": AirportSeed(cityName: "Chicago", countryCode: "US", latitude: 41.9786, longitude: -87.9048, timeZoneIdentifier: "America/Chicago"),
        "OSL": AirportSeed(cityName: "Oslo", countryCode: "NO", latitude: 60.1939, longitude: 11.1004, timeZoneIdentifier: "Europe/Oslo"),
        "PEK": AirportSeed(cityName: "Beijing", countryCode: "CN", latitude: 40.0801, longitude: 116.5846, timeZoneIdentifier: "Asia/Shanghai"),
        "PEN": AirportSeed(cityName: "Penang", countryCode: "MY", latitude: 5.2971, longitude: 100.2761, timeZoneIdentifier: "Asia/Kuala_Lumpur"),
        "PKX": AirportSeed(cityName: "Beijing", countryCode: "CN", latitude: 39.5099, longitude: 116.4108, timeZoneIdentifier: "Asia/Shanghai"),
        "PNH": AirportSeed(cityName: "Phnom Penh", countryCode: "KH", latitude: 11.5466, longitude: 104.8441, timeZoneIdentifier: "Asia/Phnom_Penh"),
        "PUS": AirportSeed(cityName: "Busan", countryCode: "KR", latitude: 35.1795, longitude: 128.9382, timeZoneIdentifier: "Asia/Seoul"),
        "PVG": AirportSeed(cityName: "Shanghai", countryCode: "CN", latitude: 31.1434, longitude: 121.8052, timeZoneIdentifier: "Asia/Shanghai"),
        "RGN": AirportSeed(cityName: "Yangon", countryCode: "MM", latitude: 16.9068, longitude: 96.1332, timeZoneIdentifier: "Asia/Yangon"),
        "RUH": AirportSeed(cityName: "Riyadh", countryCode: "SA", latitude: 24.9576, longitude: 46.6987, timeZoneIdentifier: "Asia/Riyadh"),
        "SEA": AirportSeed(cityName: "Seattle", countryCode: "US", latitude: 47.4502, longitude: -122.3088, timeZoneIdentifier: "America/Los_Angeles"),
        "SFO": AirportSeed(cityName: "San Francisco", countryCode: "US", latitude: 37.6213, longitude: -122.3790, timeZoneIdentifier: "America/Los_Angeles"),
        "SGN": AirportSeed(cityName: "Ho Chi Minh City", countryCode: "VN", latitude: 10.8188, longitude: 106.6520, timeZoneIdentifier: "Asia/Ho_Chi_Minh"),
        "SHA": AirportSeed(cityName: "Shanghai", countryCode: "CN", latitude: 31.1981, longitude: 121.3363, timeZoneIdentifier: "Asia/Shanghai"),
        "SIN": AirportSeed(cityName: "Singapore", countryCode: "SG", latitude: 1.3644, longitude: 103.9915, timeZoneIdentifier: "Asia/Singapore"),
        "SYD": AirportSeed(cityName: "Sydney", countryCode: "AU", latitude: -33.9399, longitude: 151.1753, timeZoneIdentifier: "Australia/Sydney"),
        "SZX": AirportSeed(cityName: "Shenzhen", countryCode: "CN", latitude: 22.6393, longitude: 113.8107, timeZoneIdentifier: "Asia/Shanghai"),
        "TPE": AirportSeed(cityName: "Taipei", countryCode: "TW", latitude: 25.0799, longitude: 121.2342, timeZoneIdentifier: "Asia/Taipei"),
        "USM": AirportSeed(cityName: "Samui", countryCode: "TH", latitude: 9.5478, longitude: 100.0623, timeZoneIdentifier: "Asia/Bangkok"),
        "VIE": AirportSeed(cityName: "Vienna", countryCode: "AT", latitude: 48.1103, longitude: 16.5697, timeZoneIdentifier: "Europe/Vienna"),
        "VTE": AirportSeed(cityName: "Vientiane", countryCode: "LA", latitude: 17.9883, longitude: 102.5632, timeZoneIdentifier: "Asia/Vientiane"),
        "WUH": AirportSeed(cityName: "Wuhan", countryCode: "CN", latitude: 30.7838, longitude: 114.2081, timeZoneIdentifier: "Asia/Shanghai"),
        "XIY": AirportSeed(cityName: "Xi'an", countryCode: "CN", latitude: 34.4471, longitude: 108.7519, timeZoneIdentifier: "Asia/Shanghai"),
        "XMN": AirportSeed(cityName: "Xiamen", countryCode: "CN", latitude: 24.5440, longitude: 118.1276, timeZoneIdentifier: "Asia/Shanghai"),
        "YVR": AirportSeed(cityName: "Vancouver", countryCode: "CA", latitude: 49.1951, longitude: -123.1779, timeZoneIdentifier: "America/Vancouver"),
        "YYZ": AirportSeed(cityName: "Toronto", countryCode: "CA", latitude: 43.6777, longitude: -79.6248, timeZoneIdentifier: "America/Toronto"),
        "ZRH": AirportSeed(cityName: "Zurich", countryCode: "CH", latitude: 47.4581, longitude: 8.5554, timeZoneIdentifier: "Europe/Zurich")
    ]
}
