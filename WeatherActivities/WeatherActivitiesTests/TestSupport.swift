import Foundation
@testable import WeatherActivities

// MARK: - Fixtures

extension City {
    static let london = City(
        id: 2643743, name: "London", admin1: "England", country: "United Kingdom",
        latitude: 51.50853, longitude: -0.12574, timeZoneIdentifier: "Europe/London"
    )
    static let paris = City(
        id: 2988507, name: "Paris", admin1: "Île-de-France", country: "France",
        latitude: 48.85341, longitude: 2.3488, timeZoneIdentifier: "Europe/Paris"
    )
}

extension DailyWeather {
    /// A mild, dry, lightly windy day. Override only what a test cares about.
    static func fixture(
        date: Date = DayStamp.date(from: "2026-10-30")!,
        weatherCode: Int = 1,
        temperatureMax: Double = 20,
        temperatureMin: Double = 12,
        precipitationSum: Double = 0,
        snowfallSum: Double = 0,
        precipitationProbabilityMax: Double? = 0,
        windSpeedMax: Double = 10,
        windGustsMax: Double? = 20
    ) -> DailyWeather {
        DailyWeather(
            date: date,
            weatherCode: weatherCode,
            temperatureMax: temperatureMax,
            temperatureMin: temperatureMin,
            precipitationSum: precipitationSum,
            snowfallSum: snowfallSum,
            precipitationProbabilityMax: precipitationProbabilityMax,
            windSpeedMax: windSpeedMax,
            windGustsMax: windGustsMax
        )
    }

    /// `count` consecutive identical days starting 2026-10-30 (noon UTC).
    static func week(count: Int = 7, template: DailyWeather = .fixture()) -> [DailyWeather] {
        let start = DayStamp.date(from: "2026-10-30")!
        return (0..<count).map { offset in
            DailyWeather(
                date: start.addingTimeInterval(TimeInterval(offset) * 86_400),
                weatherCode: template.weatherCode,
                temperatureMax: template.temperatureMax,
                temperatureMin: template.temperatureMin,
                precipitationSum: template.precipitationSum,
                snowfallSum: template.snowfallSum,
                precipitationProbabilityMax: template.precipitationProbabilityMax,
                windSpeedMax: template.windSpeedMax,
                windGustsMax: template.windGustsMax
            )
        }
    }
}

// MARK: - Thread-safe recorder

/// Collects values from `@Sendable` closures and services.
final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

// MARK: - Mock HTTP client

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    enum Outcome {
        case success(Data, statusCode: Int)
        case failure(Error)
    }

    private let lock = NSLock()
    private let outcome: Outcome
    private var recorded: [URLRequest] = []

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    convenience init(json: String, statusCode: Int = 200) {
        self.init(outcome: .success(Data(json.utf8), statusCode: statusCode))
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        recorded.append(request)
        let current = outcome
        lock.unlock()

        switch current {
        case let .success(data, statusCode):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        case let .failure(error):
            throw error
        }
    }
}

func queryItems(of request: URLRequest) -> [String: String] {
    guard
        let url = request.url,
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else {
        return [:]
    }
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

// MARK: - Stub services

struct StubGeocodingService: GeocodingService {
    let handler: @Sendable (String) async throws -> [City]

    func searchCities(matching query: String) async throws -> [City] {
        try await handler(query)
    }
}

struct StubWeatherService: WeatherService {
    let handler: @Sendable (City) async throws -> [DailyWeather]

    func dailyForecast(for city: City) async throws -> [DailyWeather] {
        try await handler(city)
    }
}

/// Fixed scores per activity, to test ranking independently of the weather rules.
struct ClosureScorer: ActivityScoring {
    let scoreFor: @Sendable (Activity, DailyWeather) -> Double

    func score(_ activity: Activity, for day: DailyWeather) -> Double {
        scoreFor(activity, day)
    }
}

// MARK: - Gate for deterministic concurrency tests

/// Lets a test hold an async call "in flight" and release it on demand.
actor Gate {
    private var isOpen = false
    private var hasWaiter = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    /// Called by the code under test; suspends until `open()`.
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
            hasWaiter = true
            observer?.resume()
            observer = nil
        }
    }

    /// Called by the test; returns once something is suspended in `wait()`.
    func waitUntilWaiting() async {
        if hasWaiter { return }
        await withCheckedContinuation { continuation in
            observer = continuation
        }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}
