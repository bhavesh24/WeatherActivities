import Foundation

/// Scores how suitable an activity is on a single day, from 0 (unsuitable) to 100 (ideal).
protocol ActivityScoring: Sendable {
    func score(_ activity: Activity, for day: DailyWeather) -> Double
}

/// Small helpers for turning a measurement into a 0...1 suitability factor.
enum Curve {
    /// 0 at `start`, 1 at `end`, linear in between, clamped outside.
    /// Works in both directions: `from: 6, to: 0` means "0 at 6 or above, 1 at 0 or below".
    static func ramp(_ value: Double, from start: Double, to end: Double) -> Double {
        guard start != end else { return value >= end ? 1 : 0 }
        return min(1, max(0, (value - start) / (end - start)))
    }

    /// 1 between `fullFrom` and `fullUntil`, falling to 0 at `zeroBelow` and `zeroAbove`.
    static func plateau(
        _ value: Double,
        zeroBelow: Double,
        fullFrom: Double,
        fullUntil: Double,
        zeroAbove: Double
    ) -> Double {
        min(
            ramp(value, from: zeroBelow, to: fullFrom),
            ramp(value, from: zeroAbove, to: fullUntil)
        )
    }
}

/// Rule-based scoring from daily forecast values. The rules and thresholds are documented
/// in the README ("Activity recommendation logic"); keep the two in sync.
struct WeatherActivityScorer: ActivityScoring {

    func score(_ activity: Activity, for day: DailyWeather) -> Double {
        let raw: Double
        switch activity {
        case .skiing:
            raw = skiing(day)
        case .surfing:
            raw = surfing(day)
        case .outdoorSightseeing:
            raw = outdoorSightseeing(day)
        case .indoorSightseeing:
            raw = indoorSightseeing(day)
        }
        return min(100, max(0, raw))
    }

    // MARK: - Skiing

    /// Needs snow and cold. Without fresh snowfall the score is 0 (we have no snow-depth data).
    private func skiing(_ day: DailyWeather) -> Double {
        guard day.temperatureMax < 6 else { return 0 }

        let snow = Curve.ramp(day.snowfallSum, from: 0, to: 5)
        let cold = Curve.ramp(day.temperatureMax, from: 6, to: 0)
        let gusts = day.windGustsMax ?? day.windSpeedMax
        let calm = Curve.ramp(gusts, from: 70, to: 35)

        return 100 * snow * (0.6 + 0.2 * cold + 0.2 * calm)
    }

    // MARK: - Surfing

    /// Proxy score: the Forecast API has no wave data, so we use wind (which drives swell and
    /// chop), air temperature (comfort) and rain. Thunderstorms are never suitable.
    private func surfing(_ day: DailyWeather) -> Double {
        guard !day.isThunderstorm else { return 0 }

        let wind = Curve.plateau(
            day.windSpeedMax,
            zeroBelow: 5, fullFrom: 12, fullUntil: 28, zeroAbove: 50
        )
        let warmth = Curve.plateau(
            day.temperatureMax,
            zeroBelow: 8, fullFrom: 16, fullUntil: 30, zeroAbove: 38
        )
        let dry = Curve.ramp(day.precipitationSum, from: 15, to: 2)

        return 100 * (0.5 * wind + 0.3 * warmth + 0.2 * dry)
    }

    // MARK: - Outdoor sightseeing

    /// Comfortable temperature and light wind, scaled down by rain. Thunderstorms score 0.
    private func outdoorSightseeing(_ day: DailyWeather) -> Double {
        guard !day.isThunderstorm else { return 0 }

        let temperature = Curve.plateau(
            day.temperatureMax,
            zeroBelow: 3, fullFrom: 14, fullUntil: 26, zeroAbove: 36
        )
        let calm = Curve.ramp(day.windSpeedMax, from: 50, to: 25)
        let comfort = 0.6 * temperature + 0.4 * calm

        return 100 * comfort * (0.2 + 0.8 * dryness(day))
    }

    // MARK: - Indoor sightseeing

    /// Always a reasonable option (floor of 40), and the better the worse the outdoor day is.
    private func indoorSightseeing(_ day: DailyWeather) -> Double {
        let outdoor = outdoorSightseeing(day)
        return 40 + 0.6 * (100 - outdoor)
    }

    // MARK: - Shared

    /// 1 = completely dry, 0 = heavy rain. Blends expected amount with the chance of rain
    /// when the probability is available.
    private func dryness(_ day: DailyWeather) -> Double {
        let amount = Curve.ramp(day.precipitationSum, from: 10, to: 0.5)
        guard let probability = day.precipitationProbabilityMax else { return amount }
        let chance = Curve.ramp(probability, from: 80, to: 10)
        return 0.6 * amount + 0.4 * chance
    }
}
