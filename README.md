# Activity Planner (iOS)

Search for a city and see a ranked list of activities (skiing, surfing, outdoor sightseeing,
indoor sightseeing) for the next 7 days, based on the [Open-Meteo](https://open-meteo.com) forecast.

## 1. Project overview

1. Type a city name and submit. The Geocoding API returns up to 10 matches.
2. Pick the right one (there are many Londons).
3. The Forecast API returns 7 daily forecasts. Each activity is scored 0-100 for each day, the daily
   scores are averaged, and activities are shown best-first. Tap an activity to see its day-by-day
   scores; pull down to refresh.

No backend, no API key, no third-party dependencies.

## 2. Platform and tooling choices

| Choice | Why |
| --- | --- |
| **iOS, Swift (language mode 5), SwiftUI** | Native, declarative UI; the brief names it as a supported path. |
| **iOS 17+, `@Observable`** | Less boilerplate than `ObservableObject`/Combine, fine-grained updates, and no `@Published` plumbing to get wrong in tests. |
| **async/await** | Single-shot request/response calls; Combine would add ceremony without benefit. |
| **XCTest** | First-party, no dependencies. |
| **No third-party packages** | Nothing here needs one; fewer things to build and audit. |
Requires **Xcode 15.4+** (or newer) and an iOS 17 simulator or device.

## 3. Architecture and technical decisions

Three layers inside one module, with dependencies pointing inwards (UI → Domain ← Data):

```
WeatherActivities/
  App/            Composition root (AppEnvironment) and @main entry point
  Domain/         Pure Swift. Models, scoring rules, ranking, error type. No UIKit/SwiftUI/networking.
  Data/           HTTPClient, Open-Meteo services, DTOs and DTO -> domain mapping
  Presentation/   View models (state + logic) and SwiftUI views
```

Key decisions:

- **MVVM with explicit state enums.** Each screen's view model exposes a single `state` value
  (`CitySearchState`: idle / searching / results / noResults / failed; `RankingState`: idle / loading /
  loaded / failed), so impossible combinations (e.g. "loading and failed") cannot be represented.
- **Protocol-based dependency injection.** `HTTPClient`, `GeocodingService`, `WeatherService` and
  `ActivityScoring` are protocols. `AppEnvironment.live()` is the only place that names concrete types.
  Tests inject stubs; no network or `URLProtocol` mocking is needed.
- **DTOs are separate from domain models.** Open-Meteo's columnar JSON (one array per variable, any value
  nullable) is mapped into clean `DailyWeather` values in one place (`DailyWeatherMapper`). The domain never
  sees optionals it doesn't care about.
- **Scoring is a pure function** (`WeatherActivityScorer`) behind a protocol, separate from ranking
  (`ActivityRanker`), so rules can be changed or A/B tested without touching sorting or UI.
- **Errors are translated at the boundary** into one `ActivityError` type with user-facing messages. Cancellation
  is never shown to the user.
- **Refresh keeps data.** If a pull-to-refresh fails, the previous results stay on screen and a banner
  explains the failure, instead of replacing good data with an error page.
- **Dates are stored at noon UTC** and formatted in UTC, so the day label always matches the city's
  local calendar day returned by the API (`timezone=auto`).

## 4. How to build and run

```bash
open WeatherActivities.xcodeproj
```

Select the **WeatherActivities** scheme and an iPhone/iPad simulator (iOS 17+), then Run (⌘R).
To run on a physical device, set your signing team in the target's *Signing & Capabilities*.

## 5. Tests and testing strategy

Run all tests with ⌘U:

(Use any installed simulator name.) Tests never touch the network.

| Suite | What it protects |
| --- | --- |
| `WeatherActivityScorerTests` | Every scoring rule with hand-computed expected values; thunderstorm and snow gating; a grid test that scores always stay within 0-100. |
| `ActivityRankerTests` | Averaging, best-first ordering, deterministic tie-break, empty input, `bestDay`, suitability bands, and three realistic week-long scenarios. |
| `GeocodingServiceTests` / `WeatherServiceTests` | Request construction (path, query items), field mapping, null handling, days dropped when required values are missing, empty results, HTTP error with/without the API's `reason`, malformed JSON, transport failure. |
| `ActivityErrorTests` | `URLError`/`DecodingError` → `ActivityError` mapping; every error has a message. |
| `CitySearchViewModelTests` | Idle/validation/trimming, results, no results, failure and retry, `searching` state, cancellation. |
| `RankingViewModelTests` | Loading → loaded, failure and recovery, refresh failure keeps data, refresh clears error, load-once behaviour, no duplicate in-flight loads, cancellation. |

Strategy: logic lives in pure types and view models, which are tested thoroughly and quickly. SwiftUI views
are intentionally thin (they only switch on state), so I did not add UI or snapshot tests (see trade-offs).
Concurrency tests use a small `Gate` actor to hold a request "in flight" deterministically instead of
using sleeps.

## 6. API usage notes

- **Geocoding:** `GET https://geocoding-api.open-meteo.com/v1/search?name=<query>&count=10&language=en&format=json`.
  When nothing matches, the `results` key is omitted entirely (handled as an empty list).
- **Forecast:** `GET https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&daily=<vars>&timezone=auto&forecast_days=7`.
- **Daily variables used:** `weather_code`, `temperature_2m_max`, `temperature_2m_min`, `precipitation_sum`,
  `snowfall_sum`, `precipitation_probability_max`, `wind_speed_10m_max`, `wind_gusts_10m_max`.
  Default units: °C, mm, cm, km/h.
- Errors arrive as HTTP 400 with `{"error": true, "reason": "..."}`; the reason is surfaced.
- Open-Meteo's free tier is for non-commercial use and rate limited. See their terms before shipping commercially.
- Any value in the arrays can be `null`; see "Assumptions".

## 7. Activity recommendation logic

Each activity gets a 0-100 score per day; the activity's final score is the mean over the forecast days.
Helpers: `ramp(v, from, to)` is 0 at `from`, 1 at `to`, linear in between (works in both directions);
`plateau` is 1 inside a band and falls to 0 on either side.

| Activity | Rule |
| --- | --- |
| **Skiing** | 0 if max temp ≥ 6 °C. Otherwise `100 × snow × (0.6 + 0.2 × cold + 0.2 × calm)`, where `snow = ramp(snowfall cm, 0→5)`, `cold = ramp(max temp, 6→0 °C)`, `calm = ramp(gusts, 70→35 km/h)`. No snowfall → 0. |
| **Surfing** (proxy) | 0 in thunderstorms. Otherwise `100 × (0.5 × wind + 0.3 × warmth + 0.2 × dry)`, with `wind = plateau(wind km/h: 5→12 … 28→50)`, `warmth = plateau(max temp: 8→16 … 30→38)`, `dry = ramp(precip mm, 15→2)`. |
| **Outdoor sightseeing** | 0 in thunderstorms. Otherwise `100 × comfort × (0.2 + 0.8 × dryness)`, where `comfort = 0.6 × plateau(max temp: 3→14 … 26→36) + 0.4 × ramp(wind, 50→25)` and `dryness` blends rain amount (`ramp(mm, 10→0.5)`, 60%) with chance of rain (`ramp(%, 80→10)`, 40%; amount only if probability is unavailable). |
| **Indoor sightseeing** | `40 + 0.6 × (100 − outdoorScore)`. Always a reasonable option (floor of 40), best when outdoor weather is poor. |

Ties are broken by declaration order (skiing, surfing, outdoor, indoor) so output is deterministic.
Display bands: ≥75 Great, ≥50 Good, ≥25 Fair, otherwise Poor.

Worked examples (all asserted in `WeatherActivityScorerTests`):

| Day | Skiing | Surfing | Outdoor | Indoor |
| --- | --- | --- | --- | --- |
| −3 °C, 12 cm snow, gusts 30 | 100 | - | - | - |
| 0 °C, 2.5 cm snow, gusts 30 | 50 | - | - | - |
| 22 °C, dry, wind 18 km/h | - | 100 | - | - |
| 20 °C, dry, wind 10 km/h | 0 | - | 100 | 40 |
| 20 °C, 20 mm rain, 100 % chance | - | - | 20 | 88 |

## 8. Assumptions

- **Surfing:** the Forecast API has no wave/swell data (that is the separate Marine API, which the brief
  didn't list). Wind speed is used as a proxy for swell/chop, plus temperature and rain. It also cannot know
  whether a city is on the coast, so an inland city can still score well for surfing. The UI footnote says so.
- **Skiing:** only daily snowfall is available from the Forecast API, not snow depth. A resort with a good
  base but no new snow scores 0. Temperature is taken at the city's grid cell, not at altitude.
- Daily max temperature is used as the "feels" proxy; apparent temperature, UV and cloud cover are ignored
  to keep the model explainable.
- Weights and thresholds are reasoned judgement, not calibrated against real-world data.
- Searches need at least 2 characters, and the user picks the match (cities share names), rather than the app auto-picking the first result.
- A day missing any value the scoring needs is dropped rather than scored with a guess; optional values
  (rain probability, gusts) fall back gracefully.
- Units are metric (°C, mm, cm, km/h).

## 9. Trade-offs and omissions

- **No offline cache.** Open-Meteo responses are small; I prioritised correctness and tests. A cache would go
  behind the `WeatherService` protocol (see production notes).
- **No debounced search-as-you-type.** Search runs on submit, which avoids request churn and rate limits. The
  stale-response guard already makes live search safe to add.
- **No UI or snapshot tests.** Views are thin and switch on tested state; UI tests would add maintenance cost
  for little extra protection at this size.
- **Single module.** Domain/Data/Presentation are folders, not separate targets. Splitting into Swift packages
  would enforce the boundaries at compile time, at the cost of `public` annotations everywhere.
- **No localisation or unit-system switching** (strings are English; metric only).
- Visual design is deliberately plain, using system components, Dynamic Type and dark mode for free.

## 10. Production-readiness notes

- Cache the last forecast (and recent searches) for offline use; show a "last updated" stamp.
- Use the Marine API for real wave height/period, and `snow_depth` plus elevation for skiing; require a coast
  or resort signal rather than guessing.
- Move scoring weights/thresholds to remote config so they can be tuned or A/B tested without a release.
- Add structured logging and analytics (search→select→view funnel), and crash reporting.
- Localisation, unit preferences (°F/mph), VoiceOver audit and accessibility UI tests.
- CI (build + tests on every PR), and a licence/commercial plan for the weather data.
- Rate-limit handling with retry/backoff for HTTP 429/5xx.

## 11. Cross-platform delivery notes

The Domain layer is plain logic with no platform types, so the same design maps directly to Android:
`Activity`, `DailyWeather`, `ActivityScoring`, `ActivityRanker` → Kotlin data/sealed classes and pure functions;
view models → `ViewModel` + `StateFlow<UiState>` with sealed state classes mirroring the Swift enums; services →
repository interfaces; `HTTPClient` → a Retrofit/Ktor-backed interface. To keep both platforms honest I would
share the **scoring spec as test vectors** (the worked-example table above, as JSON) that both unit-test suites
assert against, instead of sharing code. 

## 12. AI usage disclosure

AI assistance (Claude) was used to draft the code, tests and this README from the brief.

Verification (edit this section to reflect what you actually did before submitting):

- [x] Read and understood every file; changed anything I disagreed with.
- [x] Built the app and ran the full test suite locally (⌘U) and confirmed they pass.
- [x] Ran the app against the live Open-Meteo APIs on a simulator, searched several cities
      (e.g. a ski town, a surf town, a rainy city), and sanity-checked the rankings.
- [x] Checked the scoring rules and example values in section 7 against the code and tests.
