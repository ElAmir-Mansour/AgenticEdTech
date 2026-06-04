import Foundation

class APIClient {
    static let shared = APIClient()
    
    var baseURL = URL(string: "http://localhost:8080")!
    var token: String? = nil
    
    enum NetworkError: Error, LocalizedError {
        case invalidURL
        case noData
        case decodingError(Error)
        case httpError(statusCode: Int)
        case requestFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "The endpoint URL is invalid."
            case .noData: return "No data returned from server."
            case .decodingError(let error): return "Failed to decode response: \(error.localizedDescription)"
            case .httpError(let code): return "HTTP server error status: \(code)"
            case .requestFailed(let message): return "Network request failed: \(message)"
            }
        }
    }
    
    private init() {}
    
    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        var baseStr = baseURL.absoluteString
        if baseStr.hasSuffix("/") {
            baseStr = String(baseStr.dropLast())
        }
        var pathStr = path
        if !pathStr.hasPrefix("/") {
            pathStr = "/" + pathStr
        }
        
        guard let url = URL(string: "\(baseStr)\(pathStr)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.requestFailed("Invalid response object received.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                if let errorObj = try? JSONDecoder().decode(ServerErrorDetail.self, from: data), let detail = errorObj.detail {
                    throw NetworkError.requestFailed(detail)
                } else {
                    throw NetworkError.requestFailed("Server error (\(httpResponse.statusCode)): \(errorString)")
                }
            }
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateStr = try container.decode(String.self)
                if let date = formatter.date(from: dateStr) {
                    return date
                }
                let fallback = ISO8601DateFormatter()
                if let date = fallback.date(from: dateStr) {
                    return date
                }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date string: \(dateStr)")
            }
            
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
    
    func upload<T: Decodable>(
        path: String,
        fileData: Data,
        filename: String,
        mimeType: String
    ) async throws -> T {
        var baseStr = baseURL.absoluteString
        if baseStr.hasSuffix("/") {
            baseStr = String(baseStr.dropLast())
        }
        var pathStr = path
        if !pathStr.hasPrefix("/") {
            pathStr = "/" + pathStr
        }
        
        guard let url = URL(string: "\(baseStr)\(pathStr)") else {
            throw NetworkError.invalidURL
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        var body = Data()
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.requestFailed("Invalid response object received.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                if let errorObj = try? JSONDecoder().decode(ServerErrorDetail.self, from: data), let detail = errorObj.detail {
                    throw NetworkError.requestFailed(detail)
                } else {
                    throw NetworkError.requestFailed("Server error (\(httpResponse.statusCode)): \(errorString)")
                }
            }
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateStr = try container.decode(String.self)
                if let date = formatter.date(from: dateStr) {
                    return date
                }
                let fallback = ISO8601DateFormatter()
                if let date = fallback.date(from: dateStr) {
                    return date
                }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date string: \(dateStr)")
            }
            
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}

struct ServerErrorDetail: Decodable {
    let detail: String?
}

