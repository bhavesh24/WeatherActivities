import Foundation

/// Composition root: the one place that knows which concrete implementations are used.
struct AppEnvironment {
    let geocodingService: any GeocodingService
    let weatherService: any WeatherService
    let ranker: ActivityRanker

    static func live(session: URLSession = .shared) -> AppEnvironment {
        let client = URLSessionHTTPClient(session: session)
        return AppEnvironment(
            geocodingService: OpenMeteoGeocodingService(client: client),
            weatherService: OpenMeteoWeatherService(client: client),
            ranker: ActivityRanker()
        )
    }

    @MainActor
    func makeSearchViewModel() -> CitySearchViewModel {
        CitySearchViewModel(service: geocodingService)
    }

    @MainActor
    func makeRankingViewModel(for city: City) -> RankingViewModel {
        RankingViewModel(city: city, weatherService: weatherService, ranker: ranker)
    }
}
