import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case notFound
    case validationError(String)
    case rateLimited
    case serverError(statusCode: Int, message: String)
    case networkTimeout
    case unreachable(String)
    case invalidResponse
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session expired or unauthorized. Please log in again."
        case .notFound:
            return "Requested resource not found on backend."
        case .validationError(let msg):
            return "Invalid request: \(msg)"
        case .rateLimited:
            return "Rate limit exceeded. Please wait a moment and try again."
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg)"
        case .networkTimeout:
            return "Connection timed out. Please check your network or backend server."
        case .unreachable(let msg):
            return "Backend unreachable (\(msg)). Make sure FastAPI is running on \(MockexaConfig.baseURL)."
        case .invalidResponse:
            return "Received invalid response from server."
        case .decodingError(let msg):
            return "Failed to parse server data: \(msg)"
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    
    private let urlSession: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60.0
        configuration.timeoutIntervalForResource = 90.0
        self.urlSession = URLSession(configuration: configuration)
    }
    
    /// Performs a GET request to the specified endpoint
    func get<T: Decodable>(endpoint: String, token: String? = nil) async throws -> T {
        let urlString = "\(MockexaConfig.baseURL)\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw APIError.unreachable("Invalid URL format: \(urlString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return try await execute(request: request)
    }
    
    /// Performs a POST request with an Encodable body
    func post<Req: Encodable, Res: Decodable>(endpoint: String, body: Req, token: String? = nil) async throws -> Res {
        let urlString = "\(MockexaConfig.baseURL)\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw APIError.unreachable("Invalid URL format: \(urlString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.validationError("Encoding request failed: \(error.localizedDescription)")
        }
        
        return try await execute(request: request)
    }
    
    /// Performs a POST request without a body (e.g. /technical/finish/{session_id})
    func postEmpty<Res: Decodable>(endpoint: String, token: String? = nil) async throws -> Res {
        let urlString = "\(MockexaConfig.baseURL)\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw APIError.unreachable("Invalid URL format: \(urlString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return try await execute(request: request)
    }

    func delete<Res: Decodable>(endpoint: String, token: String? = nil) async throws -> Res {
        let urlString = "\(MockexaConfig.baseURL)\(endpoint)"
        guard let url = URL(string: urlString) else { throw APIError.unreachable("Invalid URL format: \(urlString)") }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return try await execute(request: request)
    }
    
    /// Checks backend `/health` endpoint
    func checkHealth() async throws -> HealthResponse {
        return try await get(endpoint: "/health")
    }
    
    /// Fetches completed user session history from backend
    func fetchSessions(token: String?) async throws -> [SessionSummaryItem] {
        return try await get(endpoint: "/sessions", token: token)
    }
    
    /// Fetches detailed session report and transcript from backend
    func fetchSessionDetail(sessionId: String, token: String?) async throws -> SessionDetailItem {
        return try await get(endpoint: "/sessions/\(sessionId)", token: token)
    }

    func fetchLeaderboard(token: String?) async throws -> LeaderboardResponse {
        return try await get(endpoint: "/gd/rewards/leaderboard", token: token)
    }


    
    private func execute<T: Decodable>(request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    let bodyStr = String(data: data, encoding: .utf8) ?? "Unreadable"
                    throw APIError.decodingError("\(error.localizedDescription) (Body: \(bodyStr.prefix(200)))")
                }
            case 401:
                throw APIError.unauthorized
            case 404:
                throw APIError.notFound
            case 422:
                let msg = parseDetailMessage(from: data) ?? "Validation failed"
                throw APIError.validationError(msg)
            case 429:
                throw APIError.rateLimited
            default:
                let msg = parseDetailMessage(from: data) ?? "Server returned HTTP \(httpResponse.statusCode)"
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: msg)
            }
        } catch let apiErr as APIError {
            throw apiErr
        } catch let urlErr as URLError {
            if urlErr.code == .cancelled {
                throw CancellationError()
            } else if urlErr.code == .timedOut {
                throw APIError.networkTimeout
            } else {
                throw APIError.unreachable(urlErr.localizedDescription)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.unreachable(error.localizedDescription)
        }
    }
    
    private func parseDetailMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? String {
                return detail
            } else if let detailArray = json["detail"] as? [[String: Any]] {
                let msgs = detailArray.compactMap { $0["msg"] as? String }
                return msgs.joined(separator: "; ")
            } else if let message = json["message"] as? String {
                return message
            }
        }
        return nil
    }
}
