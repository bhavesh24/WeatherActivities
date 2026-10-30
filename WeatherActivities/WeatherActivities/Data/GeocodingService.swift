import Foundation

protocol GeocodingService: Sendable {
    func searchCities(matching query: String) async throws -> [City]
}

/// Open-Meteo Geocoding API: https://open-meteo.com/en/docs/geocoding-api
struct OpenMeteoGeocodingService: GeocodingService {
    static let defaultBaseURL = URL(string: "https://geocoding-api.open-meteo.com")!

    private let client: any HTTPClient
    private let baseURL: URL
    private let resultLimit: Int

    init(
        client: any HTTPClient,
        baseURL: URL = OpenMeteoGeocodingService.defaultBaseURL,
        resultLimit: Int = 10
    ) {
        self.client = client
        self.baseURL = baseURL
        self.resultLimit = resultLimit
    }

    func searchCities(matching query: String) async throws -> [City] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: String(resultLimit)),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else {
            throw ActivityError.unknown
        }

        let response: GeocodingResponseDTO = try await OpenMeteoRequest.perform(url, using: client)
        // `results` is omitted entirely when nothing matches.
        return (response.results ?? []).map { $0.toDomain() }
    }
}

// MARK: - DTOs

struct GeocodingResponseDTO: Decodable {
    let results: [GeocodingResultDTO]?
}

struct GeocodingResultDTO: Decodable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
    let timezone: String?

    func toDomain() -> City {
        City(
            id: id,
            name: name,
            admin1: admin1,
            country: country,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timezone
        )
    }
}
