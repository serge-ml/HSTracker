//
//  HSReplayArenaClient.swift
//  HSTracker
//

import Foundation

enum HSReplayArenaClientError: LocalizedError {
    case invalidSourceURL
    case invalidResponse
    case httpStatus(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL:
            return "The Arena class-statistics URL is invalid."
        case .invalidResponse:
            return "The Arena statistics source returned an invalid HTTP response."
        case .httpStatus(let status):
            return "The Arena statistics source returned HTTP status \(status)."
        case .emptyResponse:
            return "The Arena statistics source returned an empty response."
        }
    }
}

protocol HSReplayArenaFetching {
    func fetch(completion: @escaping (Result<Data, Error>) -> Void)
}

final class HSReplayArenaClient: HSReplayArenaFetching {
    private let session: URLSession
    private let sourceURL: URL?
    private let userAgent: String

    init(
        sourceURL: URL? = URL(
            string: HSReplayArenaClassStatsSnapshot.sourceURL
        ),
        session: URLSession? = nil,
        userAgent: String = HSReplayArenaClient.defaultUserAgent()
    ) {
        self.sourceURL = sourceURL
        self.userAgent = userAgent
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetch(completion: @escaping (Result<Data, Error>) -> Void) {
        guard let sourceURL = sourceURL else {
            completion(.failure(HSReplayArenaClientError.invalidSourceURL))
            return
        }

        var request = URLRequest(url: sourceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "https://github.com/Zero-to-Heroes/firestone",
            forHTTPHeaderField: "Referer"
        )

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(HSReplayArenaClientError.invalidResponse))
                return
            }
            guard (200...299).contains(response.statusCode) else {
                completion(
                    .failure(
                        HSReplayArenaClientError.httpStatus(response.statusCode)
                    )
                )
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(.failure(HSReplayArenaClientError.emptyResponse))
                return
            }
            completion(.success(data))
        }.resume()
    }

    private static func defaultUserAgent() -> String {
        let info = Bundle.main.infoDictionary
        let executable = info?[kCFBundleExecutableKey as String]
            as? String ?? "HSTracker"
        let appVersion = info?["CFBundleShortVersionString"]
            as? String ?? "Unknown"
        let appBuild = info?[kCFBundleVersionKey as String]
            as? String ?? "Unknown"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = [
            version.majorVersion,
            version.minorVersion,
            version.patchVersion
        ].map(String.init).joined(separator: ".")

        return "\(executable)/\(appVersion) " +
            "(build:\(appBuild); macOS \(osVersion))"
    }
}
