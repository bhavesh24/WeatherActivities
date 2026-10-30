import XCTest
@testable import WeatherActivities

final class ActivityRankerTests: XCTestCase {

    func test_rank_withNoDays_returnsNothing() {
        XCTAssertTrue(ActivityRanker().rank([]).isEmpty)
    }

    func test_rank_scoreIsTheMeanOfTheDailyScores() {
        // The stub scorer returns the day's max temperature as the score for every activity.
        let ranker = ActivityRanker(scorer: ClosureScorer { _, day in day.temperatureMax })
        let days = [
            DailyWeather.fixture(temperatureMax: 10),
            DailyWeather.fixture(temperatureMax: 20),
            DailyWeather.fixture(temperatureMax: 60)
        ]

        let skiing = ranker.rank(days).first { $0.activity == .skiing }

        XCTAssertEqual(skiing?.score ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(skiing?.dailyScores.count, 3)
    }

    func test_rank_sortsBestFirst() {
        let fixed: [Activity: Double] = [
            .skiing: 10, .surfing: 90, .outdoorSightseeing: 50, .indoorSightseeing: 70
        ]
        let ranker = ActivityRanker(scorer: ClosureScorer { activity, _ in fixed[activity] ?? 0 })

        let order = ranker.rank([.fixture()]).map(\.activity)

        XCTAssertEqual(order, [.surfing, .indoorSightseeing, .outdoorSightseeing, .skiing])
    }

    func test_rank_tiesKeepTheDeclaredActivityOrder() {
        let ranker = ActivityRanker(scorer: ClosureScorer { _, _ in 42 })

        let order = ranker.rank([.fixture()]).map(\.activity)

        XCTAssertEqual(order, Activity.allCases)
    }

    func test_bestDay_isTheHighestScoringDay_andEarliestOnATie() {
        let first = DayStamp.date(from: "2026-10-30")!
        let second = DayStamp.date(from: "2026-10-31")!
        let third = DayStamp.date(from: "2026-11-01")!
        let item = RankedActivity(
            activity: .surfing,
            score: 0,
            dailyScores: [
                DailyScore(date: first, score: 40),
                DailyScore(date: second, score: 80),
                DailyScore(date: third, score: 80)
            ]
        )

        XCTAssertEqual(item.bestDay?.date, second)
    }

    func test_suitability_bandsMatchThresholds() {
        XCTAssertEqual(Suitability(score: 100), .great)
        XCTAssertEqual(Suitability(score: 75), .great)
        XCTAssertEqual(Suitability(score: 74.9), .good)
        XCTAssertEqual(Suitability(score: 50), .good)
        XCTAssertEqual(Suitability(score: 25), .fair)
        XCTAssertEqual(Suitability(score: 24.9), .poor)
        XCTAssertEqual(Suitability(score: 0), .poor)
    }

    // MARK: Realistic scenarios with the real scoring rules

    func test_scenario_coldSnowyWeek_putsSkiingFirst() {
        let week = DailyWeather.week(template: .fixture(
            weatherCode: 73,
            temperatureMax: -3,
            temperatureMin: -9,
            precipitationSum: 8,
            snowfallSum: 12,
            precipitationProbabilityMax: nil,
            windSpeedMax: 20,
            windGustsMax: 30
        ))

        XCTAssertEqual(ActivityRanker().rank(week).first?.activity, .skiing)
    }

    func test_scenario_coldRainyWeek_putsIndoorSightseeingFirstAndSkiingLast() {
        let week = DailyWeather.week(template: .fixture(
            weatherCode: 63,
            temperatureMax: 12,
            temperatureMin: 8,
            precipitationSum: 12,
            precipitationProbabilityMax: nil,
            windSpeedMax: 30,
            windGustsMax: 45
        ))

        let order = ActivityRanker().rank(week).map(\.activity)

        XCTAssertEqual(order.first, .indoorSightseeing)
        XCTAssertEqual(order.last, .skiing)
    }

    func test_scenario_perfectBeachWeek_ranksSurfingAheadOfOutdoorOnATie() {
        let week = DailyWeather.week(template: .fixture(
            temperatureMax: 24,
            temperatureMin: 17,
            precipitationSum: 0,
            precipitationProbabilityMax: 0,
            windSpeedMax: 15,
            windGustsMax: 25
        ))

        let ranked = ActivityRanker().rank(week)

        XCTAssertEqual(ranked.map(\.activity), [.surfing, .outdoorSightseeing, .indoorSightseeing, .skiing])
        XCTAssertEqual(ranked.first?.roundedScore, 100)
        XCTAssertEqual(ranked.last?.roundedScore, 0)
    }
}
