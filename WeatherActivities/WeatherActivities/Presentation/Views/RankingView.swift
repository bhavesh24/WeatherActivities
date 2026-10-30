import SwiftUI

@MainActor
struct RankingView: View {
    @State private var viewModel: RankingViewModel

    init(viewModel: RankingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle(viewModel.city.name)
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading forecast…")

        case .loaded(let ranking):
            RankingList(ranking: ranking, refreshError: viewModel.refreshError)
                .refreshable { await viewModel.load() }

        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't load forecast", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.load() }
                }
            }
        }
    }
}

private struct RankingList: View {
    let ranking: ActivityRanking
    let refreshError: ActivityError?

    var body: some View {
        List {
            if let refreshError {
                Section {
                    Label(refreshError.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(Array(ranking.activities.enumerated()), id: \.element.id) { index, item in
                    ActivityRow(rank: index + 1, item: item)
                }
            } header: {
                Text("Best activities for the next \(ranking.days.count) days")
            } footer: {
                Text("Scores are 0–100, averaged over the forecast. Surfing is estimated from wind, temperature and rain because wave data isn't used. Skiing relies on forecast snowfall.")
            }

            Section("Forecast") {
                ForEach(ranking.days, id: \.date) { day in
                    ForecastRow(day: day)
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let rank: Int
    let item: RankedActivity

    var body: some View {
        DisclosureGroup {
            ForEach(item.dailyScores, id: \.date) { daily in
                HStack {
                    Text(DayLabel.string(from: daily.date))
                    Spacer()
                    Text("\(Int(daily.score.rounded()))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } label: {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.title3.bold())
                    .frame(width: 24)
                Image(systemName: item.activity.systemImage)
                    .frame(width: 28)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.activity.title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(item.roundedScore)")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(item.suitability.color)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var subtitle: String {
        guard let best = item.bestDay, best.score > 0 else {
            return item.suitability.label
        }
        return "\(item.suitability.label) · best \(DayLabel.string(from: best.date))"
    }
}

private struct ForecastRow: View {
    let day: DailyWeather

    var body: some View {
        let condition = WeatherCondition(code: day.weatherCode)
        HStack {
            Image(systemName: condition.symbol)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(DayLabel.string(from: day.date))
                Text(condition.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(day.temperatureMax.rounded()))° / \(Int(day.temperatureMin.rounded()))°")
                    .monospacedDigit()
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if day.snowfallSum > 0 {
            return String(format: "%.1f cm snow", day.snowfallSum)
        }
        return String(format: "%.1f mm rain", day.precipitationSum)
    }
}
