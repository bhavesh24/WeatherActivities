import Foundation

struct DailyScore: Equatable, Sendable {
    let date: Date
    let score: Double
}

enum Suitability: Equatable, Sendable {
    case great
    case good
    case fair
    case poor

    init(score: Double) {
        switch score {
        case 75...: self = .great
        case 50...: self = .good
        case 25...: self = .fair
        default: self = .poor
        }
    }
}

struct RankedActivity: Equatable, Identifiable, Sendable {
    let activity: Activity
    /// Mean of the daily scores across the forecast window, 0...100.
    let score: Double
    let dailyScores: [DailyScore]

    var id: Activity { activity }
    var roundedScore: Int { Int(score.rounded()) }
    var suitability: Suitability { Suitability(score: score) }

    /// The best day for this activity. On a tie the earliest day wins.
    var bestDay: DailyScore? {
        dailyScores.max(by: { $0.score < $1.score })
    }
}

/// The result shown to the user: a city, its forecast and the activities ranked best-first.
struct ActivityRanking: Equatable, Sendable {
    let city: City
    let days: [DailyWeather]
    let activities: [RankedActivity]
}

/// Pure ranking logic: scores every activity on every day, averages, and sorts.
struct ActivityRanker: Sendable {
    private let scorer: any ActivityScoring

    init(scorer: any ActivityScoring = WeatherActivityScorer()) {
        self.scorer = scorer
    }

    /// Returns activities ordered best-first. Ties keep the order of `Activity.allCases`,
    /// so the output is deterministic.
    func rank(_ days: [DailyWeather]) -> [RankedActivity] {
        guard !days.isEmpty else { return [] }

        let ranked = Activity.allCases.map { activity -> RankedActivity in
            let daily = days.map { day in
                DailyScore(date: day.date, score: scorer.score(activity, for: day))
            }
            let mean = daily.map(\.score).reduce(0, +) / Double(daily.count)
            return RankedActivity(activity: activity, score: mean, dailyScores: daily)
        }

        return ranked
            .enumerated()
            .sorted { lhs, rhs in
                let left = Self.sortKey(lhs.element.score)
                let right = Self.sortKey(rhs.element.score)
                if left != right {
                    return left > right
                }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    /// Compares scores at micro-point precision so floating-point noise (for example
    /// 99.99999999999999 vs 100) cannot reorder activities that are really tied.
    private static func sortKey(_ score: Double) -> Double {
        (score * 1_000_000).rounded()
    }
}
