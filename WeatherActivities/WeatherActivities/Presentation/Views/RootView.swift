import SwiftUI

@MainActor
struct RootView: View {
    private let environment: AppEnvironment
    @State private var searchViewModel: CitySearchViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _searchViewModel = State(initialValue: environment.makeSearchViewModel())
    }

    var body: some View {
        NavigationStack {
            CitySearchView(viewModel: searchViewModel)
                .navigationDestination(for: City.self) { city in
                    RankingView(viewModel: environment.makeRankingViewModel(for: city))
                }
        }
    }
}
