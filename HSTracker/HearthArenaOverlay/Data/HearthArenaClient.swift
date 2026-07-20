//
//  HearthArenaClient.swift
//  HSTracker
//

import Foundation

enum HearthArenaClientError: LocalizedError {
    case invalidSourceURL
    case invalidResponse
    case httpStatus(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL:
            return "The HearthArena tier-list URL is invalid."
        case .invalidResponse:
            return "HearthArena returned an invalid HTTP response."
        case .httpStatus(let status):
            return "HearthArena returned HTTP status \(status)."
        case .emptyResponse:
            return "HearthArena returned an empty response."
        }
    }
}

protocol HearthArenaFetching {
    func fetch(completion: @escaping (Result<Data, Error>) -> Void)
}

final class HearthArenaClient: HearthArenaFetching {
    private let session: URLSession
    private let sourceURL: URL?

    init(
        sourceURL: URL? = URL(string: TierListSnapshot.sourceURL),
        session: URLSession? = nil
    ) {
        self.sourceURL = sourceURL
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
            completion(.failure(HearthArenaClientError.invalidSourceURL))
            return
        }
        var request = URLRequest(url: sourceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(
            "HSTracker-Arena/\(TierListSnapshot.currentParserVersion)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(HearthArenaClientError.invalidResponse))
                return
            }
            guard (200...299).contains(response.statusCode) else {
                completion(.failure(HearthArenaClientError.httpStatus(response.statusCode)))
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(.failure(HearthArenaClientError.emptyResponse))
                return
            }
            completion(.success(data))
        }.resume()
    }
}
