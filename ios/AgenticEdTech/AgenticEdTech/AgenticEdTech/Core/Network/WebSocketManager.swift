import Foundation
import Observation
import Combine

@Observable
class WebSocketManager {
    static let shared = WebSocketManager()
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var isConnecting = false
    
    var isConnected = false
    
    let messagePublisher = PassthroughSubject<ServerMessage, Never>()
    
    private init() {}
    
    func connect(token: String) {
        guard !isConnected && !isConnecting else { return }
        isConnecting = true
        
        let base = APIClient.shared.baseURL
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.scheme = base.scheme == "https" ? "wss" : "ws"
        components?.path = "/ws"
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        
        guard let url = components?.url else {
            isConnecting = false
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        self.receiveMessage()
        self.startPingTimer()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        isConnecting = false
        stopPingTimer()
    }
    
    func send(message: ClientMessage) {
        guard isConnected else { return }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            if let jsonString = String(data: data, encoding: .utf8) {
                let taskMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask?.send(taskMessage) { error in
                    if let error = error {
                        print("WebSocket send error: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            print("WebSocket message serialization failed: \(error.localizedDescription)")
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.parseMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.parseMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()
                
            case .failure(let error):
                print("WebSocket disconnect or receive error: \(error.localizedDescription)")
                self.handleDisconnection()
            }
        }
    }
    
    private func parseMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let decoder = JSONDecoder()
            let serverMessage = try decoder.decode(ServerMessage.self, from: data)
            
            DispatchQueue.main.async {
                if serverMessage.type == "connection_established" {
                    self.isConnected = true
                    self.isConnecting = false
                }
                self.messagePublisher.send(serverMessage)
            }
        } catch {
            print("Failed decoding ServerMessage: \(error.localizedDescription) | raw: \(text)")
        }
    }
    
    private func startPingTimer() {
        stopPingTimer()
        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }
    
    private func stopPingTimer() {
        DispatchQueue.main.async {
            self.pingTimer?.invalidate()
            self.pingTimer = nil
        }
    }
    
    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                print("WebSocket ping error: \(error.localizedDescription)")
                self?.handleDisconnection()
            }
        }
    }
    
    private func handleDisconnection() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
            self.stopPingTimer()
        }
    }
}
