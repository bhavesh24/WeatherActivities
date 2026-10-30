import XCTest
@testable import WeatherActivities

final class GeocodingServiceTests: XCTestCase {

    private let londonResponse = #"""
    {
      "results": [
        {
          "id": 2643743, "name": "London", "latitude": 51.50853, "longitude": -0.12574,
          "elevation": 25.0, "feature_code": "PPLC", "country_code": "GB",
          "admin1_id": 6269131, "timezone": "Europe/London", "population": 8961989,
          "country_id": 2635167, "country": "United Kingdom", "admin1": "England"
        },
        {
          "id": 6058560, "name": "London", "latitude": 42.98339, "longitude": -81.23304,
          "timezone": "America/Toronto", "country": "Canada", "admin1": "Ontario"
        }
      ],
      "generationtime_ms": 0.9
    }
    """#

    func test_searchCities_mapsResultsToDomainCities() async throws {
        let service = OpenMeteoGeocodingService(client: MockHTTPClient(json: londonResponse))

        let cities = try await service.searchCities(matching: "London")

        XCTAssertEqual(cities.count, 2)
        XCTAssertEqual(cities[0].id, 2643743)
        XCTAssertEqual(cities[0].name, "London")
        XCTAssertEqual(cities[0].latitude, 51.50853, accuracy: 0.00001)
        XCTAssertEqual(cities[0].longitude, -0.12574, accuracy: 0.00001)
        XCTAssertEqual(cities[0].timeZoneIdentifier, "Europe/London")
        XCTAssertEqual(cities[0].displayName, "London, England, United Kingdom")
        XCTAssertEqual(cities[1].country, "Canada")
    }

    func test_searchCities_buildsTheExpectedRequest() async throws {
        let client = MockHTTPClient(json: londonResponse)
        let service = OpenMeteoGeocodingService(client: client)

        _ = try await service.searchCities(matching: "São Paulo")

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.host, "geocoding-api.open-meteo.com")
        XCTAssertEqual(request.url?.path, "/v1/search")
        let items = queryItems(of: request)
        XCTAssertEqual(items["name"], "São Paulo")
        XCTAssertEqual(items["count"], "10")
        XCTAssertEqual(items["language"], "en")
        XCTAssertEqual(items["format"], "json")
    }

    func test_searchCities_whenResultsKeyIsMissing_returnsEmptyArray() async throws {
        let client = MockHTTPClient(json: #"{"generationtime_ms": 0.4}"#)
        let service = OpenMeteoGeocodingService(client: client)

        let cities = try await service.searchCities(matching: "Zzzzzz")

        XCTAssertTrue(cities.isEmpty)
    }

    func test_searchCities_onHTTPErrorWithReason_throwsServerErrorCarryingReason() async {
        let client = MockHTTPClient(
            json: #"{"error": true, "reason": "Parameter 'count' must be between 1 and 100."}"#,
            statusCode: 400
        )
        let service = OpenMeteoGeocodingService(client: client)

        do {
            _ = try await service.searchCities(matching: "London")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(
                error as? ActivityError,
                .server(statusCode: 400, reason: "Parameter 'count' must be between 1 and 100.")
            )
        }
    }

    func test_searchCities_onServerErrorWithoutBody_throwsServerErrorWithNoReason() async {
        let service = OpenMeteoGeocodingService(client: MockHTTPClient(json: "", statusCode: 503))

        do {
            _ = try await service.searchCities(matching: "London")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ActivityError, .server(statusCode: 503, reason: nil))
        }
    }

    func test_searchCities_onMalformedJSON_throwsInvalidResponse() async {
        let service = OpenMeteoGeocodingService(client: MockHTTPClient(json: "not json"))

        do {
            _ = try await service.searchCities(matching: "London")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ActivityError, .invalidResponse)
        }
    }

    func test_searchCities_onTransportFailure_propagatesTheError() async {
        let client = MockHTTPClient(outcome: .failure(ActivityError.offline))
        let service = OpenMeteoGeocodingService(client: client)

        do {
            _ = try await service.searchCities(matching: "London")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ActivityError, .offline)
        }
    }
}
