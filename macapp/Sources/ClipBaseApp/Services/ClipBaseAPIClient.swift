import Foundation

struct ClipBaseAPIClient {
    private let session: URLSession

    struct LoginResponse: Decodable {
        let username: String
        let token: String?
    }

    struct SyncResponse: Decodable {
        let serverTime: Int64
        let changes: SyncChanges
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func login(baseURL: String, username: String, password: String) async throws -> LoginResponse {
        var request = try jsonRequest(baseURL: baseURL, path: "/api/login", method: "POST", token: nil)
        request.httpBody = try JSONEncoder().encode([
            "username": username,
            "password": password,
            "tokenMode": "bearer"
        ])

        let response: LoginResponse = try await perform(request)
        guard response.token?.isEmpty == false else {
            throw APIError.message("登入成功但伺服器未回傳 Bearer token")
        }
        return response
    }

    func logout(baseURL: String, token: String) async {
        guard var request = try? jsonRequest(baseURL: baseURL, path: "/api/logout", method: "POST", token: token) else {
            return
        }
        request.httpBody = Data()
        _ = try? await session.data(for: request)
    }

    func pullSync(baseURL: String, token: String, since: Int64) async throws -> SyncResponse {
        var components = try components(baseURL: baseURL, path: "/api/sync")
        components.queryItems = [URLQueryItem(name: "since", value: String(since))]
        guard let url = components.url else {
            throw APIError.message("同步 URL 無效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func sync(baseURL: String, token: String, since: Int64, changes: SyncChanges) async throws -> SyncResponse {
        var request = try jsonRequest(baseURL: baseURL, path: "/api/sync", method: "POST", token: token)
        request.httpBody = try JSONEncoder.clipBase.encode(SyncRequest(since: since, changes: changes))
        return try await perform(request)
    }

    private func jsonRequest(baseURL: String, path: String, method: String, token: String?) throws -> URLRequest {
        guard let url = try components(baseURL: baseURL, path: path).url else {
            throw APIError.message("API URL 無效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func components(baseURL: String, path: String) throws -> URLComponents {
        let normalized = Self.normalizedBaseURL(baseURL)
        guard let url = URL(string: normalized), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.message("Base URL 無效")
        }
        components.path = path
        return components
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.message("伺服器回應格式無效")
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw APIError.message(body?.error ?? "API 請求失敗（HTTP \(httpResponse.statusCode)）")
        }

        return try JSONDecoder.clipBase.decode(T.self, from: data)
    }

    static func normalizedBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "https://clipbase.thelonesomeera.com"
        let base = trimmed.isEmpty ? fallback : trimmed
        return String(base.drop(while: { $0 == "/" })).hasPrefix("http")
            ? base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : fallback
    }
}

private struct SyncRequest: Encodable {
    let since: Int64
    let changes: SyncChanges
}

private struct ErrorResponse: Decodable {
    let error: String?
}

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "登入已過期，請重新登入"
        case .message(let message):
            return message
        }
    }
}

extension JSONEncoder {
    static var clipBase: JSONEncoder {
        JSONEncoder()
    }
}

extension JSONDecoder {
    static var clipBase: JSONDecoder {
        JSONDecoder()
    }
}
