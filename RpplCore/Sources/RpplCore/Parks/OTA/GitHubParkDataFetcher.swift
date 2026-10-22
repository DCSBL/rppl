import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads park data from the `parks-distribution` branch through raw.githubusercontent.com.
/// No cookies, no cache, no identifiers: GitHub sees an IP address and a generic request.
public struct GitHubParkDataFetcher: ParkDataFetching {
    public static let baseURL = URL(string: "https://raw.githubusercontent.com/DCSBL/rppl/parks-distribution/")!

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = GitHubParkDataFetcher.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieStorage = nil
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetch(_ path: String, maxBytes: Int) async throws -> Data {
        // `path` is a manifest-validated file name; refuse anything that could leave the branch root.
        guard !path.contains("/"), !path.contains("..") else { throw ParkDataError.fetchFailed("bad path") }
        let url = baseURL.appendingPathComponent(path)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw ParkDataError.fetchFailed("\(path): \(describeWaterTemperatureError(error))")
        }
        guard let http = response as? HTTPURLResponse else { throw ParkDataError.fetchFailed("\(path): no HTTP response") }
        guard http.statusCode == 200 else { throw ParkDataError.fetchFailed("\(path): HTTP \(http.statusCode)") }
        guard data.count <= maxBytes else { throw ParkDataError.tooLarge(path) }
        return data
    }
}
