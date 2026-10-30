import Foundation

/// Shared request/response handling for both Open-Meteo endpoints.
enum OpenMeteoRequest {
    static let timeout: TimeInterval = 15

    /// Open-Meteo reports errors as HTTP 400 with `{"error": true, "reason": "..."}`.
    private struct ErrorDTO: Decodable {
        let reason: String?
    }

    static func perform<T: Decodable>(
        _ url: URL,
        using client: any HTTPClient
    ) async throws -> T {
        let request = URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: timeout
        )
        let (data, response) = try await client.send(request)

        guard (200..<300).contains(response.statusCode) else {
            let reason = (try? JSONDecoder().decode(ErrorDTO.self, from: data))?.reason
            throw ActivityError.server(statusCode: response.statusCode, reason: reason)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ActivityError.invalidResponse
        }
    }
}
