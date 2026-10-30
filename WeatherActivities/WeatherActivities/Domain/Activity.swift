import Foundation

/// The activities we rank. The declaration order is also the tie-break order.
enum Activity: String, CaseIterable, Identifiable, Sendable {
    case skiing
    case surfing
    case outdoorSightseeing
    case indoorSightseeing

    var id: String { rawValue }
}
