import Foundation
import Observation

/// Everything the search screen can be showing. Exactly one case at a time.
enum CitySearchState: Equatable {
    case idle
    case searching
    case results([City])
    case noResults(query: String)
    case failed(ActivityError)
}

@MainActor
@Observable
final class CitySearchViewModel {
    static let minimumQueryLength = 2

    /// Bound to the search field.
    var query = ""
    private(set) var state: CitySearchState = .idle

    @ObservationIgnored private let service: any GeocodingService

    init(service: any GeocodingService) {
        self.service = service
    }

    func search() async {
        await search(for: query)
    }

    func search(for text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            state = .idle
            return
        }
        guard trimmed.count >= Self.minimumQueryLength else {
            state = .failed(.invalidQuery)
            return
        }

        state = .searching
        do {
            let cities = try await service.searchCities(matching: trimmed)
            state = cities.isEmpty ? .noResults(query: trimmed) : .results(cities)
        } catch is CancellationError {
                state = .idle
        } catch {
            state = .failed(ActivityError.from(error))
        }
    }
}
