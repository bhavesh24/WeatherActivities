import Foundation

/// The only networking seam in the app. Services depend on this protocol, so tests can
/// substitute canned responses without touching the network or `URLProtocol`.
protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ActivityError.invalidResponse
            }
            return (data, http)
        } catch let error as URLError {
            // A cancelled request is a normal event (the user moved on), not a failure.
            if error.code == .cancelled {
                throw CancellationError()
            }
            throw ActivityError.map(urlError: error)
        }
    }
}
