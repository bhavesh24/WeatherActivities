import SwiftUI

@MainActor
struct CitySearchView: View {
    @State private var viewModel: CitySearchViewModel

    init(viewModel: CitySearchViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle("Activity Planner")
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search for a city"
            )
            .onSubmit(of: .search) {
                Task { await viewModel.search() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            ContentUnavailableView(
                "Where are you heading?",
                systemImage: "magnifyingglass",
                description: Text("Search for a city to see which activities suit the next 7 days.")
            )

        case .searching:
            ProgressView("Searching…")

        case .results(let cities):
            List(cities) { city in
                NavigationLink(value: city) {
                    CityRow(city: city)
                }
            }

        case .noResults(let query):
            ContentUnavailableView.search(text: query)

        case .failed(let error):
            ContentUnavailableView {
                Label("Search failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                if error != .invalidQuery {
                    Button("Try Again") {
                        Task { await viewModel.search() }
                    }
                }
            }
        }
    }
}

private struct CityRow: View {
    let city: City

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(city.name)
                .font(.headline)
            let detail = [city.admin1, city.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
