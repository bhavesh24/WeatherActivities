import XCTest
@testable import WeatherActivities

@MainActor
final class RankingViewModelTests: XCTestCase {

    private let week = DailyWeather.week()

    private func makeViewModel(
        handler: @escaping @Sendable (City) async throws -> [DailyWeather]
    ) -> RankingViewModel {
        RankingViewModel(city: .london, weatherService: StubWeatherService(handler: handler))
    }

    func test_initialState_isIdle() {
        let viewModel = makeViewModel { _ in [] }
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.refreshError)
    }

    func test_load_success_producesTheRankingForTheCity() async {
        let days = week
        let viewModel = makeViewModel { _ in days }

        await viewModel.load()

        let expected = ActivityRanking(
            city: .london,
            days: days,
            activities: ActivityRanker().rank(days)
        )
        XCTAssertEqual(viewModel.state, .loaded(expected))
    }

    func test_load_requestsTheForecastForTheViewModelsCity() async {
        let requested = Recorder<City>()
        let days = week
        let viewModel = makeViewModel { city in
            requested.append(city)
            return days
        }

        await viewModel.load()

        XCTAssertEqual(requested.values, [.london])
    }

    func test_load_showsLoadingWhileTheRequestIsInFlight() async {
        let gate = Gate()
        let days = week
        let viewModel = makeViewModel { _ in
            await gate.wait()
            return days
        }

        let task = Task { await viewModel.load() }
        await gate.waitUntilWaiting()
        XCTAssertEqual(viewModel.state, .loading)

        await gate.open()
        await task.value
        guard case .loaded = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
    }

    func test_load_failure_showsTheError() async {
        let viewModel = makeViewModel { _ in throw ActivityError.offline }

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.offline))
    }

    func test_load_whenThereIsNoUsableForecast_showsNoForecastData() async {
        let viewModel = makeViewModel { _ in throw ActivityError.noForecastData }

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.noForecastData))
    }

    func test_load_afterAFailure_canRecover() async {
        let calls = Recorder<City>()
        let days = week
        let viewModel = makeViewModel { city in
            calls.append(city)
            if calls.values.count == 1 { throw ActivityError.timedOut }
            return days
        }

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .failed(.timedOut))

        await viewModel.load()
        guard case .loaded = viewModel.state else {
            return XCTFail("Expected loaded, got \(viewModel.state)")
        }
    }

    func test_refresh_failure_keepsTheExistingDataAndReportsARefreshError() async {
        let calls = Recorder<City>()
        let days = week
        let viewModel = makeViewModel { city in
            calls.append(city)
            if calls.values.count == 1 { return days }
            throw ActivityError.offline
        }

        await viewModel.load()
        let loadedState = viewModel.state
        await viewModel.load()

        XCTAssertEqual(viewModel.state, loadedState, "Existing results must stay visible")
        XCTAssertEqual(viewModel.refreshError, .offline)
    }

    func test_refresh_success_clearsAPreviousRefreshError() async {
        let calls = Recorder<City>()
        let days = week
        let viewModel = makeViewModel { city in
            calls.append(city)
            if calls.values.count == 2 { throw ActivityError.offline }
            return days
        }

        await viewModel.load()
        await viewModel.load()
        XCTAssertEqual(viewModel.refreshError, .offline)

        await viewModel.load()
        XCTAssertNil(viewModel.refreshError)
    }

    func test_loadIfNeeded_loadsOnlyOnce() async {
        let calls = Recorder<City>()
        let days = week
        let viewModel = makeViewModel { city in
            calls.append(city)
            return days
        }

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        XCTAssertEqual(calls.values.count, 1)
    }

    func test_loadIfNeeded_afterAFailure_doesNotRetryAutomatically() async {
        let calls = Recorder<City>()
        let viewModel = makeViewModel { city in
            calls.append(city)
            throw ActivityError.offline
        }

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        XCTAssertEqual(calls.values.count, 1)
        XCTAssertEqual(viewModel.state, .failed(.offline))
    }

    func test_load_whenCancelledBeforeAnyData_returnsToIdle() async {
        let viewModel = makeViewModel { _ in throw CancellationError() }

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .idle)
    }

    func test_load_whileAlreadyLoading_doesNotStartASecondRequest() async {
        let gate = Gate()
        let calls = Recorder<City>()
        let days = week
        let viewModel = makeViewModel { city in
            calls.append(city)
            await gate.wait()
            return days
        }

        let first = Task { await viewModel.load() }
        await gate.waitUntilWaiting()

        await viewModel.load() // returns immediately: a load is already in flight
        XCTAssertEqual(calls.values.count, 1)

        await gate.open()
        await first.value
    }
}
