import Foundation

/// Shared URLSession configured with generous timeouts for large media API calls
enum APISession {
    /// URLSession with 10-minute request timeout and 30-minute resource timeout
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600    // 10 minutes per request
        config.timeoutIntervalForResource = 1800  // 30 minutes total
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
}
