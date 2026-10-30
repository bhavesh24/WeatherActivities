import XCTest
@testable import WeatherActivities

@MainActor
final class CitySearchViewModelTests: XCTestCase {

    private func makeViewModel(
        handler: @escaping @Sendable (String) async throws -> [City]
    ) -> CitySearchViewModel {
        CitySearchViewModel(service: StubGeocodingService(handler: handler))
    }

    func test_initialState_isIdle() {
        let viewModel = makeViewModel { _ in [] }
        XCTAssertEqual(viewModel.state, .idle)
    }

    func test_search_withBlankQuery_staysIdleAndDoesNotCallTheService() async {
        let calls = Recorder<String>()
        let viewModel = makeViewModel { query in
            calls.append(query)
            return []
        }

        await viewModel.search(for: "   ")

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(calls.values.isEmpty)
    }

    func test_search_withASingleCharacter_failsValidationWithoutCallingTheService() async {
        let calls = Recorder<String>()
        let viewModel = makeViewModel { query in
            calls.append(query)
            return []
        }

        await viewModel.search(for: "L")

        XCTAssertEqual(viewModel.state, .failed(.invalidQuery))
        XCTAssertTrue(calls.values.isEmpty)
    }

    func test_search_trimsWhitespaceBeforeCallingTheService() async {
        let calls = Recorder<String>()
        let viewModel = makeViewModel { query in
            calls.append(query)
            return [.london]
        }

        await viewModel.search(for: "  London \n")

        XCTAssertEqual(calls.values, ["London"])
    }

    func test_search_withMatches_showsResults() async {
        let viewModel = makeViewModel { _ in [.london, .paris] }

        await viewModel.search(for: "lon")

        XCTAssertEqual(viewModel.state, .results([.london, .paris]))
    }

    func test_search_withNoMatches_showsNoResultsForThatQuery() async {
        let viewModel = makeViewModel { _ in [] }

        await viewModel.search(for: "Zzzzzz")

        XCTAssertEqual(viewModel.state, .noResults(query: "Zzzzzz"))
    }

    func test_search_whenTheServiceFails_showsTheError() async {
        let viewModel = makeViewModel { _ in throw ActivityError.offline }

        await viewModel.search(for: "London")

        XCTAssertEqual(viewModel.state, .failed(.offline))
    }

    func test_search_whenAnUnexpectedErrorIsThrown_showsUnknown() async {
        struct Surprise: Error {}
        let viewModel = makeViewModel { _ in throw Surprise() }

        await viewModel.search(for: "London")

        XCTAssertEqual(viewModel.state, .failed(.unknown))
    }

    func test_search_afterAFailure_canSucceedOnRetry() async {
        let calls = Recorder<String>()
        let viewModel = makeViewModel { query in
            calls.append(query)
            if calls.values.count == 1 { throw ActivityError.timedOut }
            return [.london]
        }

        await viewModel.search(for: "London")
        XCTAssertEqual(viewModel.state, .failed(.timedOut))

        await viewModel.search(for: "London")
        XCTAssertEqual(viewModel.state, .results([.london]))
    }

    func test_search_usesTheBoundQueryProperty() async {
        let calls = Recorder<String>()
        let viewModel = makeViewModel { query in
            calls.append(query)
            return [.paris]
        }
        viewModel.query = "Paris"

        await viewModel.search()

        XCTAssertEqual(calls.values, ["Paris"])
        XCTAssertEqual(viewModel.state, .results([.paris]))
    }

    func test_search_showsSearchingWhileTheRequestIsInFlight() async {
        let gate = Gate()
        let viewModel = makeViewModel { _ in
            await gate.wait()
            return [.london]
        }

        let task = Task { await viewModel.search(for: "London") }
        await gate.waitUntilWaiting()
        XCTAssertEqual(viewModel.state, .searching)

        await gate.open()
        await task.value
        XCTAssertEqual(viewModel.state, .results([.london]))
    }

    func test_search_whenCancelled_returnsToIdleInsteadOfShowingAnError() async {
        let viewModel = makeViewModel { _ in throw CancellationError() }

        await viewModel.search(for: "London")

        XCTAssertEqual(viewModel.state, .idle)
    }
}
