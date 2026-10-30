import Foundation
import Observation

/// Everything the ranking screen can be showing. Exactly one case at a time.
enum RankingState: Equatable {
    case idle
    case loading
    case loaded(ActivityRanking)
    case failed(ActivityError)
}

@MainActor
@Observable
final class RankingViewModel {
    let city: City
    private(set) var state: RankingState = .idle
    /// Set when a refresh fails while we already have data to show. The old data stays visible.
    private(set) var refreshError: ActivityError?

    @ObservationIgnored private let weatherService: any WeatherService
    @ObservationIgnored private let ranker: ActivityRanker

    init(
        city: City,
        weatherService: any WeatherService,
        ranker: ActivityRanker = ActivityRanker()
    ) {
        self.city = city
        self.weatherService = weatherService
        self.ranker = ranker
    }

    /// Loads on first appearance only, so navigating back to the screen does not refetch.
    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await load()
    }

    /// Fetches and ranks. Safe to call again for retry or pull-to-refresh.
    func load() async {
        if case .loading = state { return }

        let hadData: Bool
        if case .loaded = state {
            hadData = true
        } else {
            hadData = false
            state = .loading
        }
        refreshError = nil

        do {
            let days = try await weatherService.dailyForecast(for: city)
            let ranking = ActivityRanking(
                city: city,
                days: days,
                activities: ranker.rank(days)
            )
            state = .loaded(ranking)
        } catch is CancellationError {
            if !hadData {
                state = .idle
            }
        } catch {
            let activityError = ActivityError.from(error)
            if hadData {
                refreshError = activityError
            } else {
                state = .failed(activityError)
            }
        }
    }
}
