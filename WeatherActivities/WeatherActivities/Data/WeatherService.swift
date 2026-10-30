import Foundation

protocol WeatherService: Sendable {
    func dailyForecast(for city: City) async throws -> [DailyWeather]
}

/// Open-Meteo Forecast API: https://open-meteo.com/en/docs
struct OpenMeteoWeatherService: WeatherService {
    static let defaultBaseURL = URL(string: "https://api.open-meteo.com")!
    static let forecastDays = 7

    /// The daily variables we request. Keep in sync with `ForecastResponseDTO.Daily`.
    static let dailyVariables = [
        "weather_code",
        "temperature_2m_max",
        "temperature_2m_min",
        "precipitation_sum",
        "snowfall_sum",
        "precipitation_probability_max",
        "wind_speed_10m_max",
        "wind_gusts_10m_max"
    ]

    private let client: any HTTPClient
    private let baseURL: URL

    init(
        client: any HTTPClient,
        baseURL: URL = OpenMeteoWeatherService.defaultBaseURL
    ) {
        self.client = client
        self.baseURL = baseURL
    }

    func dailyForecast(for city: City) async throws -> [DailyWeather] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/forecast"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "daily", value: Self.dailyVariables.joined(separator: ",")),
            // "auto" makes each day a local calendar day for the searched city.
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(Self.forecastDays))
        ]
        guard let url = components?.url else {
            throw ActivityError.unknown
        }

        let response: ForecastResponseDTO = try await OpenMeteoRequest.perform(url, using: client)
        let days = DailyWeatherMapper.map(response.daily)
        guard !days.isEmpty else {
            throw ActivityError.noForecastData
        }
        return days
    }
}

// MARK: - DTOs

/// Open-Meteo returns "columnar" data: one array per variable, index-aligned with `time`.
/// Any value can be `null`, so every element is optional.
struct ForecastResponseDTO: Decodable {
    let daily: Daily

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Double?]
        let temperatureMax: [Double?]
        let temperatureMin: [Double?]
        let precipitationSum: [Double?]
        let snowfallSum: [Double?]
        let precipitationProbabilityMax: [Double?]?
        let windSpeedMax: [Double?]
        let windGustsMax: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case precipitationSum = "precipitation_sum"
            case snowfallSum = "snowfall_sum"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case windSpeedMax = "wind_speed_10m_max"
            case windGustsMax = "wind_gusts_10m_max"
        }
    }
}

// MARK: - Mapping

enum DailyWeatherMapper {
    /// Converts columnar data into days. A day missing any value we depend on is dropped
    /// rather than scored with guessed numbers; optional values stay `nil`.
    static func map(_ dto: ForecastResponseDTO.Daily) -> [DailyWeather] {
        dto.time.indices.compactMap { index -> DailyWeather? in
            guard
                let date = DayStamp.date(from: dto.time[index]),
                let code = value(dto.weatherCode, at: index),
                let temperatureMax = value(dto.temperatureMax, at: index),
                let temperatureMin = value(dto.temperatureMin, at: index),
                let precipitation = value(dto.precipitationSum, at: index),
                let snowfall = value(dto.snowfallSum, at: index),
                let windSpeed = value(dto.windSpeedMax, at: index)
            else {
                return nil
            }

            return DailyWeather(
                date: date,
                weatherCode: Int(code),
                temperatureMax: temperatureMax,
                temperatureMin: temperatureMin,
                precipitationSum: precipitation,
                snowfallSum: snowfall,
                precipitationProbabilityMax: value(dto.precipitationProbabilityMax, at: index),
                windSpeedMax: windSpeed,
                windGustsMax: value(dto.windGustsMax, at: index)
            )
        }
    }

    private static func value(_ array: [Double?]?, at index: Int) -> Double? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

/// Parses Open-Meteo's "yyyy-MM-dd" day strings.
enum DayStamp {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// Returns noon UTC on that calendar day, so formatting in UTC always shows the same day.
    static func date(from string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        return calendar.date(from: components)
    }
}
