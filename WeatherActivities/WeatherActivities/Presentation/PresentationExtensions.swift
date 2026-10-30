import SwiftUI

// Display concerns live here so the Domain layer stays free of UI and copy.

extension Activity {
    var title: String {
        switch self {
        case .skiing: return "Skiing"
        case .surfing: return "Surfing"
        case .outdoorSightseeing: return "Outdoor sightseeing"
        case .indoorSightseeing: return "Indoor sightseeing"
        }
    }

    var systemImage: String {
        switch self {
        case .skiing: return "figure.skiing.downhill"
        case .surfing: return "figure.surfing"
        case .outdoorSightseeing: return "binoculars"
        case .indoorSightseeing: return "building.columns"
        }
    }
}

extension Suitability {
    var label: String {
        switch self {
        case .great: return "Great"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    /// Colour reinforces the text label; it is never the only signal.
    var color: Color {
        switch self {
        case .great: return .green
        case .good: return .mint
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

/// Short description and SF Symbol for a WMO weather code.
struct WeatherCondition: Equatable {
    let description: String
    let symbol: String

    init(code: Int) {
        switch code {
        case 0:
            self.init(description: "Clear sky", symbol: "sun.max")
        case 1, 2:
            self.init(description: "Partly cloudy", symbol: "cloud.sun")
        case 3:
            self.init(description: "Overcast", symbol: "cloud")
        case 45, 48:
            self.init(description: "Fog", symbol: "cloud.fog")
        case 51...57:
            self.init(description: "Drizzle", symbol: "cloud.drizzle")
        case 61...67:
            self.init(description: "Rain", symbol: "cloud.rain")
        case 71...77:
            self.init(description: "Snow", symbol: "cloud.snow")
        case 80...82:
            self.init(description: "Rain showers", symbol: "cloud.heavyrain")
        case 85, 86:
            self.init(description: "Snow showers", symbol: "cloud.snow")
        case 95...99:
            self.init(description: "Thunderstorm", symbol: "cloud.bolt.rain")
        default:
            self.init(description: "Unknown", symbol: "questionmark.circle")
        }
    }

    private init(description: String, symbol: String) {
        self.description = description
        self.symbol = symbol
    }
}

enum DayLabel {
    /// "Fri 30 Oct". Days are stored at noon UTC, so format in UTC to avoid date-line shifts.
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: date)
    }
}
