import Foundation

/// One day of forecast data, in the units Open-Meteo returns by default
/// (°C, mm, cm, km/h) for the city's local calendar day.
struct DailyWeather: Equatable, Sendable {
    /// Local calendar day, stored as noon UTC so it never shifts across a date line when displayed.
    let date: Date
    /// WMO weather interpretation code.
    let weatherCode: Int
    let temperatureMax: Double
    let temperatureMin: Double
    /// Total liquid-equivalent precipitation (rain, showers, melted snow), in mm.
    let precipitationSum: Double
    /// Total snowfall, in cm.
    let snowfallSum: Double
    /// Highest hourly chance of precipitation, in %. Not available for every location/model.
    let precipitationProbabilityMax: Double?
    /// Highest 10 m wind speed, in km/h.
    let windSpeedMax: Double
    /// Highest 10 m wind gust, in km/h. Not always available.
    let windGustsMax: Double?

    /// WMO codes 95, 96 and 99 are thunderstorms.
    var isThunderstorm: Bool {
        weatherCode >= 95
    }
}
