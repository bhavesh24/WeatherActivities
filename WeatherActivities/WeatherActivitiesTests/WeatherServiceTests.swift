import XCTest
@testable import WeatherActivities

final class WeatherServiceTests: XCTestCase {

    private let threeDays = #"""
    {
      "latitude": 51.5, "longitude": -0.12, "timezone": "Europe/London",
      "daily": {
        "time": ["2026-10-30", "2026-10-31", "2026-11-01"],
        "weather_code": [3, 61, 95],
        "temperature_2m_max": [14.2, 12.0, 11.5],
        "temperature_2m_min": [8.1, 7.0, 6.2],
        "precipitation_sum": [0.0, 5.4, 12.0],
        "snowfall_sum": [0.0, 0.0, 0.0],
        "precipitation_probability_max": [10, 80, null],
        "wind_speed_10m_max": [15.0, 22.5, 30.1],
        "wind_gusts_10m_max": [30.2, 40.0, 55.5]
      }
    }
    """#

    func test_dailyForecast_mapsEveryField() async throws {
        let service = OpenMeteoWeatherService(client: MockHTTPClient(json: threeDays))

        let days = try await service.dailyForecast(for: .london)

        XCTAssertEqual(days.count, 3)
        let first = days[0]
        XCTAssertEqual(first.date, DayStamp.date(from: "2026-10-30"))
        XCTAssertEqual(first.weatherCode, 3)
        XCTAssertEqual(first.temperatureMax, 14.2, accuracy: 0.001)
        XCTAssertEqual(first.temperatureMin, 8.1, accuracy: 0.001)
        XCTAssertEqual(first.precipitationSum, 0, accuracy: 0.001)
        XCTAssertEqual(first.snowfallSum, 0, accuracy: 0.001)
        XCTAssertEqual(first.precipitationProbabilityMax, 10)
        XCTAssertEqual(first.windSpeedMax, 15, accuracy: 0.001)
        XCTAssertEqual(first.windGustsMax, 30.2)
        XCTAssertTrue(days[2].isThunderstorm)
    }

    func test_dailyForecast_keepsNullOptionalValuesAsNil() async throws {
        let service = OpenMeteoWeatherService(client: MockHTTPClient(json: threeDays))

        let days = try await service.dailyForecast(for: .london)

        XCTAssertNil(days[2].precipitationProbabilityMax)
        XCTAssertNotNil(days[1].precipitationProbabilityMax)
    }

    func test_dailyForecast_buildsTheExpectedRequest() async throws {
        let client = MockHTTPClient(json: threeDays)
        let service = OpenMeteoWeatherService(client: client)

        _ = try await service.dailyForecast(for: .london)

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.host, "api.open-meteo.com")
        XCTAssertEqual(request.url?.path, "/v1/forecast")
        let items = queryItems(of: request)
        XCTAssertEqual(items["latitude"], "51.50853")
        XCTAssertEqual(items["longitude"], "-0.12574")
        XCTAssertEqual(items["timezone"], "auto")
        XCTAssertEqual(items["forecast_days"], "7")
        let requested = Set((items["daily"] ?? "").split(separator: ",").map(String.init))
        XCTAssertEqual(requested, Set(OpenMeteoWeatherService.dailyVariables))
        XCTAssertTrue(requested.contains("snowfall_sum"))
        XCTAssertTrue(requested.contains("wind_speed_10m_max"))
    }

    func test_dailyForecast_dropsDaysMissingRequiredValues() async throws {
        let json = #"""
        {
          "daily": {
            "time": ["2026-10-30", "2026-10-31", "2026-11-01"],
            "weather_code": [3, 61, 1],
            "temperature_2m_max": [14.2, null, 11.5],
            "temperature_2m_min": [8.1, 7.0, 6.2],
            "precipitation_sum": [0.0, 5.4, 0.0],
            "snowfall_sum": [0.0, 0.0, 0.0],
            "wind_speed_10m_max": [15.0, 22.5, 30.1]
          }
        }
        """#
        let service = OpenMeteoWeatherService(client: MockHTTPClient(json: json))

        let days = try await service.dailyForecast(for: .london)

        XCTAssertEqual(days.map(\.date), [
            DayStamp.date(from: "2026-10-30")!,
            DayStamp.date(from: "2026-11-01")!
        ])
    }

    func test_dailyForecast_whenOptionalArraysAreAbsent_stillSucceeds() async throws {
        let json = #"""
        {
          "daily": {
            "time": ["2026-10-30"],
            "weather_code": [0],
            "temperature_2m_max": [20.0],
            "temperature_2m_min": [10.0],
            "precipitation_sum": [0.0],
            "snowfall_sum": [0.0],
            "wind_speed_10m_max": [12.0]
          }
        }
        """#
        let service = OpenMeteoWeatherService(client: MockHTTPClient(json: json))

        let days = try await service.dailyForecast(for: .london)

        XCTAssertEqual(days.count, 1)
        XCTAssertNil(days[0].precipitationProbabilityMax)
        XCTAssertNil(days[0].windGustsMax)
    }

    func test_dailyForecast_whenNoDayIsUsable_throwsNoForecastData() async {
        let json = #"""
        {
          "daily": {
            "time": ["2026-10-30"],
            "weather_code": [null],
            "temperature_2m_max": [null],
            "temperature_2m_min": [null],
            "precipitation_sum": [null],
            "snowfall_sum": [null],
            "wind_speed_10m_max": [null]
          }
        }
        """#
        let service = OpenMeteoWeatherService(client: MockHTTPClient(json: json))

        do {
            _ = try await service.dailyForecast(for: .london)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ActivityError, .noForecastData)
        }
    }

    func test_dailyForecast_whenDailyBlockIsMissing_throwsInvalidResponse() async {
        let service = OpenMeteoWeatherService(client: MockHTTPClient(json: #"{"latitude": 1}"#))

        do {
            _ = try await service.dailyForecast(for: .london)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? ActivityError, .invalidResponse)
        }
    }

    func test_dailyForecast_onHTTPError_throwsServerError() async {
        let client = MockHTTPClient(json: #"{"error": true, "reason": "Latitude must be in range of -90 to 90°."}"#, statusCode: 400)
        let service = OpenMeteoWeatherService(client: client)

        do {
            _ = try await service.dailyForecast(for: .london)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(
                error as? ActivityError,
                .server(statusCode: 400, reason: "Latitude must be in range of -90 to 90°.")
            )
        }
    }
}

final class ActivityErrorTests: XCTestCase {

    func test_urlErrors_mapToFriendlyErrors() {
        XCTAssertEqual(ActivityError.from(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(ActivityError.from(URLError(.networkConnectionLost)), .offline)
        XCTAssertEqual(ActivityError.from(URLError(.timedOut)), .timedOut)
        XCTAssertEqual(ActivityError.from(URLError(.badServerResponse)), .unknown)
    }

    func test_decodingErrors_mapToInvalidResponse() {
        let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        XCTAssertEqual(ActivityError.from(error), .invalidResponse)
    }

    func test_activityErrors_passThroughUnchanged() {
        XCTAssertEqual(ActivityError.from(ActivityError.noForecastData), .noForecastData)
    }

    func test_unknownErrors_mapToUnknown() {
        struct Surprise: Error {}
        XCTAssertEqual(ActivityError.from(Surprise()), .unknown)
    }

    func test_everyErrorHasAUserFacingMessage() {
        let errors: [ActivityError] = [
            .invalidQuery, .offline, .timedOut,
            .server(statusCode: 500, reason: nil),
            .server(statusCode: 400, reason: "Bad parameter"),
            .invalidResponse, .noForecastData, .unknown
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error)")
        }
    }
}
