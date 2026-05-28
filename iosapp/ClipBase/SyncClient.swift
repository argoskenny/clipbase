import Foundation

protocol SyncServicing {
    func login(baseURL: String, username: String, password: String) async throws -> LoginResponse
    func logout(baseURL: String, token: String) async
    func sync(baseURL: String, token: String, since: Milliseconds, changes: SyncChanges) async throws -> SyncResponse
}

final class SyncClient: SyncServicing {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func login(baseURL: String, username: String, password: String) async throws -> LoginResponse {
        var request = try request(baseURL: baseURL, path: "/api/login", method: "POST")
        request.httpBody = try encoder.encode(LoginRequest(username: username, password: password, tokenMode: "bearer", client: "native"))
        let data = try await perform(request, treatsUnauthorizedAsLoginFailure: true)
        return try decoder.decode(LoginResponse.self, from: data)
    }

    func logout(baseURL: String, token: String) async {
        guard var request = try? request(baseURL: baseURL, path: "/api/logout", method: "POST") else {
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    func sync(baseURL: String, token: String, since: Milliseconds, changes: SyncChanges) async throws -> SyncResponse {
        var request = try request(baseURL: baseURL, path: "/api/sync", method: "POST")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(SyncRequest(since: since, changes: changes))
        let data = try await perform(request)
        return try decoder.decode(SyncResponse.self, from: data)
    }

    private func request(baseURL: String, path: String, method: String) throws -> URLRequest {
        guard let base = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SyncClientError.invalidURL
        }
        let url = base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest, treatsUnauthorizedAsLoginFailure: Bool = false) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncClientError.server("伺服器沒有回應")
        }
        if http.statusCode == 401 {
            if treatsUnauthorizedAsLoginFailure {
                let payload = try? decoder.decode(APIErrorPayload.self, from: data)
                throw SyncClientError.server(payload?.error ?? "帳號或密碼不正確")
            }
            throw SyncClientError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(APIErrorPayload.self, from: data)
            throw SyncClientError.server(payload?.error ?? "請求失敗：\(http.statusCode)")
        }
        return data
    }
}

private struct LoginRequest: Encodable {
    var username: String
    var password: String
    var tokenMode: String
    var client: String
}

private struct SyncRequest: Encodable {
    var since: Milliseconds
    var changes: SyncChanges
}

private struct APIErrorPayload: Decodable {
    var error: String?
}

enum SyncClientError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Server URL 格式不正確"
        case .unauthorized:
            return "登入已過期，請重新登入"
        case .server(let message):
            return message
        }
    }
}
