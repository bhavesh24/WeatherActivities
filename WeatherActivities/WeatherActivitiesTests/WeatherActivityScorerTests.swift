import XCTest
@testable import WeatherActivities

/// Expected values are worked out by hand from the rules in the README, so a failing test
/// means either the rules or the documentation changed.
final class WeatherActivityScorerTests: XCTestCase {
    private let scorer = WeatherActivityScorer()
    private let accuracy = 0.001

    private func score(_ activity: Activity, _ day: DailyWeather) -> Double {
        scorer.score(activity, for: day)
    }

    // MARK: Skiing

    func test_skiing_coldWithHeavySnowAndCalmWind_isPerfect() {
        let day = DailyWeather.fixture(temperatureMax: -3, snowfallSum: 12, windGustsMax: 30)
        XCTAssertEqual(score(.skiing, day), 100, accuracy: accuracy)
    }

    func test_skiing_withoutSnowfall_isZero() {
        let day = DailyWeather.fixture(temperatureMax: -5, snowfallSum: 0)
        XCTAssertEqual(score(.skiing, day), 0, accuracy: accuracy)
    }

    func test_skiing_whenTooWarm_isZeroEvenWithSnowfall() {
        let day = DailyWeather.fixture(temperatureMax: 8, snowfallSum: 10)
        XCTAssertEqual(score(.skiing, day), 0, accuracy: accuracy)
    }

    func test_skiing_halfTheSnowTarget_halvesTheScore() {
        let day = DailyWeather.fixture(temperatureMax: 0, snowfallSum: 2.5, windGustsMax: 30)
        XCTAssertEqual(score(.skiing, day), 50, accuracy: accuracy)
    }

    func test_skiing_strongGusts_reduceTheScore() {
        let day = DailyWeather.fixture(temperatureMax: -2, snowfallSum: 10, windGustsMax: 70)
        XCTAssertEqual(score(.skiing, day), 80, accuracy: accuracy)
    }

    // MARK: Surfing

    func test_surfing_moderateWindWarmAndDry_isPerfect() {
        let day = DailyWeather.fixture(temperatureMax: 22, precipitationSum: 0, windSpeedMax: 18)
        XCTAssertEqual(score(.surfing, day), 100, accuracy: accuracy)
    }

    func test_surfing_calmWind_losesTheWindShareOfTheScore() {
        let day = DailyWeather.fixture(temperatureMax: 22, precipitationSum: 0, windSpeedMax: 2)
        XCTAssertEqual(score(.surfing, day), 50, accuracy: accuracy)
    }

    func test_surfing_thunderstorm_isZero() {
        let day = DailyWeather.fixture(weatherCode: 95, temperatureMax: 22, windSpeedMax: 18)
        XCTAssertEqual(score(.surfing, day), 0, accuracy: accuracy)
    }

    // MARK: Outdoor sightseeing

    func test_outdoorSightseeing_mildDryCalmDay_isPerfect() {
        XCTAssertEqual(score(.outdoorSightseeing, .fixture()), 100, accuracy: accuracy)
    }

    func test_outdoorSightseeing_heavyRain_isHeavilyPenalised() {
        let day = DailyWeather.fixture(precipitationSum: 20, precipitationProbabilityMax: 100)
        XCTAssertEqual(score(.outdoorSightseeing, day), 20, accuracy: accuracy)
    }

    func test_outdoorSightseeing_thunderstorm_isZero() {
        let day = DailyWeather.fixture(weatherCode: 99)
        XCTAssertEqual(score(.outdoorSightseeing, day), 0, accuracy: accuracy)
    }

    func test_outdoorSightseeing_withoutProbability_usesRainAmountAlone() {
        let withProbability = DailyWeather.fixture(precipitationSum: 20, precipitationProbabilityMax: 0)
        let withoutProbability = DailyWeather.fixture(precipitationSum: 20, precipitationProbabilityMax: nil)
        XCTAssertGreaterThan(
            score(.outdoorSightseeing, withProbability),
            score(.outdoorSightseeing, withoutProbability)
        )
    }

    // MARK: Indoor sightseeing

    func test_indoorSightseeing_onPerfectOutdoorDay_stillHasAFloorOf40() {
        XCTAssertEqual(score(.indoorSightseeing, .fixture()), 40, accuracy: accuracy)
    }

    func test_indoorSightseeing_inHeavyRain_scoresHigh() {
        let day = DailyWeather.fixture(precipitationSum: 20, precipitationProbabilityMax: 100)
        XCTAssertEqual(score(.indoorSightseeing, day), 88, accuracy: accuracy)
    }

    func test_indoorSightseeing_isBetterThanOutdoor_whenWeatherIsBad() {
        let day = DailyWeather.fixture(weatherCode: 95, precipitationSum: 30, windSpeedMax: 60)
        XCTAssertGreaterThan(score(.indoorSightseeing, day), score(.outdoorSightseeing, day))
    }

    // MARK: Invariants

    func test_scores_alwaysStayWithinZeroToOneHundred() {
        let temperatures: [Double] = Array(stride(from: -30.0, through: 50.0, by: 5.0))
        let precipitation: [Double] = [0, 1, 5, 20, 80]
        let snowfall: [Double] = [0, 2, 10, 40]
        let winds: [Double] = [0, 10, 30, 60, 120]
        let codes = [0, 3, 61, 95]
        let probabilities: [Double?] = [nil, 0, 50, 100]
        var violations: [String] = []

        for temperature in temperatures {
            for rain in precipitation {
                for snow in snowfall {
                    for wind in winds {
                        for code in codes {
                            for probability in probabilities {
                                let day = DailyWeather.fixture(
                                    weatherCode: code,
                                    temperatureMax: temperature,
                                    temperatureMin: temperature - 5,
                                    precipitationSum: rain,
                                    snowfallSum: snow,
                                    precipitationProbabilityMax: probability,
                                    windSpeedMax: wind,
                                    windGustsMax: wind * 1.5
                                )
                                for activity in Activity.allCases {
                                    let value = score(activity, day)
                                    if !(0...100).contains(value) {
                                        violations.append("\(activity) scored \(value) for \(day)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "\(violations.count) out-of-range scores, e.g. \(violations.prefix(3))"
        )
    }

    func test_curveRamp_clampsAndSupportsDescendingRanges() {
        XCTAssertEqual(Curve.ramp(-1, from: 0, to: 10), 0, accuracy: accuracy)
        XCTAssertEqual(Curve.ramp(5, from: 0, to: 10), 0.5, accuracy: accuracy)
        XCTAssertEqual(Curve.ramp(20, from: 0, to: 10), 1, accuracy: accuracy)
        XCTAssertEqual(Curve.ramp(8, from: 6, to: 0), 0, accuracy: accuracy)
        XCTAssertEqual(Curve.ramp(3, from: 6, to: 0), 0.5, accuracy: accuracy)
        XCTAssertEqual(Curve.ramp(-4, from: 6, to: 0), 1, accuracy: accuracy)
    }
}
