import Foundation

struct City: Equatable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let admin1: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String?

    /// "London, England, United Kingdom" - skips parts the API did not provide.
    var displayName: String {
        [name, admin1, country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
