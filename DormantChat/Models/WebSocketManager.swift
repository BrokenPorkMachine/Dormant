import Foundation
import Network

/// Connection state for WebSocket
enum ConnectionState: String, CaseIterable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed
    
    var displayName: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .failed:
            return "Connection Failed"
        }
    }
    
    var isConnected: Bool {
        return self == .connected
    }
}

/// WebSocket message types
enum WebSocketMessageType: String, Codable {
    case chatMessage = "chat_message"
    case joinRoom = "join_room"
    case leaveRoom = "leave_room"
    case roomUpdate = "room_update"
    case userPresence = "user_presence"
    case error = "error"
    case ping = "ping"
    case pong = "pong"
}

/// WebSocket message envelope
struct WebSocketMessage: Codable {
    let type: WebSocketMessageType
    let roomId: UUID?
    let payload: Data
    let timestamp: Date
    let messageId: UUID
    
    init(type: WebSocketMessageType, roomId: UUID? = nil, payload: Data, timestamp: Date = Date()) {
        self.type = type
        self.roomId = roomId
        self.payload = payload
        self.timestamp = timestamp
        self.messageId = UUID()
    }
}

/// WebSocket client manager for real-time communication
@MainActor
class WebSocketManager: NSObject, ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentRoom: ChatRoom?
    @Published var lastError: Error?
    
    // WebSocket connection
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    
    // Connection management
    private var serverURL: URL?
    private var reconnectAttempts: Int = 0
    private var maxReconnectAttempts: Int = 10
    private var reconnectDelay: TimeInterval = 1.0
    private var maxReconnectDelay: TimeInterval = 30.0
    
    // Message handling
    private var messageQueue: [WebSocketMessage] = []
    private var isProcessingQueue: Bool = false
    
    // Ping/Pong for connection health
    private var pingTimer: Timer?
    private var pingInterval: TimeInterval = 30.0
    private var lastPongReceived: Date = Date()
    
    // Encryption
    private var encryptionManager: E2EEncryptionManager?
    
    override init() {
        super.init()
        setupURLSession()
    }
    
    // MARK: - Connection Management
    
    /// Connect to the WebSocket server
    /// - Parameter serverURL: The WebSocket server URL
    func connect(to serverURL: URL) async throws {
        guard connectionState != .connecting && connectionState != .connected else {
            print("Already connecting or connected")
            return
        }
        
        self.serverURL = serverURL
        connectionState = .connecting
        lastError = nil
        
        do {
            try await establishConnection()
            connectionState = .connected
            reconnectAttempts = 0
            startPingTimer()
            await processMessageQueue()
            print("WebSocket connected to \(serverURL)")
        } catch {
            connectionState = .failed
            lastError = error
            print("WebSocket connection failed: \(error)")
            throw error
        }
    }
    
    /// Disconnect from the WebSocket server
    func disconnect() {
        connectionState = .disconnected
        stopPingTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        currentRoom = nil
        messageQueue.removeAll()
        print("WebSocket disconnected")
    }
    
    /// Reconnect with exponential backoff
    private func reconnectWithBackoff() async {
        guard let serverURL = serverURL,
              reconnectAttempts < maxReconnectAttempts,
              connectionState != .connected else {
            connectionState = .failed
            return
        }
        
        connectionState = .reconnecting
        reconnectAttempts += 1
        
        let delay = min(reconnectDelay * pow(2.0, Double(reconnectAttempts - 1)), maxReconnectDelay)
        print("Reconnecting in \(delay) seconds (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")
        
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        do {
            try await connect(to: serverURL)
        } catch {
            print("Reconnection attempt \(reconnectAttempts) failed: \(error)")
            await reconnectWithBackoff()
        }
    }
    
    // MARK: - Room Management
    
    /// Generate a new room key for encryption
    /// - Returns: The room key data
    static func generateRoomKey() -> Data {
        let manager = E2EEncryptionManager.generateNewRoomKey()
        return manager.getRoomKeyData()
    }
    
    /// Create a shareable room key string
    /// - Parameter keyData: The room key data
    /// - Returns: Base64 encoded shareable key
    static func createShareableRoomKey(from keyData: Data) throws -> String {
        let manager = try E2EEncryptionManager(key: keyData)
        return manager.createShareableKey()
    }
    
    /// Parse a shareable room key string
    /// - Parameter shareableKey: Base64 encoded room key
    /// - Returns: The room key data
    /// - Throws: WebSocketError if the key is invalid
    static func parseShareableRoomKey(_ shareableKey: String) throws -> Data {
        do {
            let manager = try E2EEncryptionManager.fromShareableKey(shareableKey)
            return manager.getRoomKeyData()
        } catch {
            throw WebSocketError.encryptionFailed
        }
    }
    
    /// Join a chat room
    /// - Parameters:
    ///   - roomId: The room ID to join
    ///   - encryptionKey: Optional encryption key for the room
    func joinRoom(_ roomId: UUID, encryptionKey: Data? = nil) async throws {
        guard connectionState.isConnected else {
            throw WebSocketError.notConnected
        }
        
        // Set up encryption if key provided
        if let key = encryptionKey {
            encryptionManager = try E2EEncryptionManager(key: key)
        }
        
        let joinRequest = RoomJoinRequest(roomId: roomId, userId: getCurrentUserId())
        let payload = try JSONEncoder().encode(joinRequest)
        
        let message = WebSocketMessage(
            type: .joinRoom,
            roomId: roomId,
            payload: payload
        )
        
        try await sendMessage(message)
        
        // Update current room (this would normally be confirmed by server response)
        currentRoom = ChatRoom(
            id: roomId,
            name: "Room \(roomId.uuidString.prefix(8))",
            participants: [getCurrentUserId()],
            encryptionEnabled: encryptionKey != nil,
            encryptionKey: encryptionKey,
            createdAt: Date()
        )
        
        print("Joined room \(roomId)")
    }
    
    /// Leave the current room
    func leaveRoom() async throws {
        guard let room = currentRoom else {
            throw WebSocketError.notInRoom
        }
        
        let leaveRequest = RoomLeaveRequest(roomId: room.id, userId: getCurrentUserId())
        let payload = try JSONEncoder().encode(leaveRequest)
        
        let message = WebSocketMessage(
            type: .leaveRoom,
            roomId: room.id,
            payload: payload
        )
        
        try await sendMessage(message)
        
        currentRoom = nil
        encryptionManager = nil
        
        print("Left room \(room.id)")
    }
    
    // MARK: - Message Handling
    
    /// Send a chat message
    /// - Parameter message: The chat message to send
    func sendMessage(_ chatMessage: ChatMessage) async throws {
        guard let room = currentRoom else {
            throw WebSocketError.notInRoom
        }
        
        guard connectionState.isConnected else {
            throw WebSocketError.notConnected
        }
        
        // Encrypt message if encryption is enabled
        var messageData = try JSONEncoder().encode(chatMessage)
        if let encryptionManager = encryptionManager {
            messageData = try encryptionManager.encrypt(messageData)
        }
        
        let wsMessage = WebSocketMessage(
            type: .chatMessage,
            roomId: room.id,
            payload: messageData
        )
        
        try await sendMessage(wsMessage)
        print("Sent message to room \(room.id)")
    }
    
    /// Send a WebSocket message
    /// - Parameter message: The WebSocket message to send
    private func sendMessage(_ message: WebSocketMessage) async throws {
        guard let webSocketTask = webSocketTask else {
            throw WebSocketError.notConnected
        }
        
        if connectionState.isConnected {
            let messageData = try JSONEncoder().encode(message)
            let wsMessage = URLSessionWebSocketTask.Message.data(messageData)
            try await webSocketTask.send(wsMessage)
        } else {
            // Queue message for later sending
            messageQueue.append(message)
        }
    }
    
    /// Process queued messages when connection is restored
    private func processMessageQueue() async {
        guard !isProcessingQueue && connectionState.isConnected else { return }
        
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        while !messageQueue.isEmpty && connectionState.isConnected {
            let message = messageQueue.removeFirst()
            do {
                try await sendMessage(message)
            } catch {
                print("Failed to send queued message: \(error)")
                // Re-queue the message
                messageQueue.insert(message, at: 0)
                break
            }
        }
    }
    
    // MARK: - Message Reception
    
    /// Handle incoming WebSocket messages
    private func handleIncomingMessage(_ data: Data) {
        do {
            let wsMessage = try JSONDecoder().decode(WebSocketMessage.self, from: data)
            
            switch wsMessage.type {
            case .chatMessage:
                handleChatMessage(wsMessage)
            case .roomUpdate:
                handleRoomUpdate(wsMessage)
            case .userPresence:
                handleUserPresence(wsMessage)
            case .pong:
                handlePong()
            case .error:
                handleError(wsMessage)
            default:
                print("Unhandled message type: \(wsMessage.type)")
            }
        } catch {
            print("Failed to decode WebSocket message: \(error)")
        }
    }
    
    private func handleChatMessage(_ wsMessage: WebSocketMessage) {
        do {
            // Decrypt message if encryption is enabled
            var messageData = wsMessage.payload
            if let encryptionManager = encryptionManager {
                messageData = try encryptionManager.decrypt(messageData)
            }
            
            let chatMessage = try JSONDecoder().decode(ChatMessage.self, from: messageData)
            
            // Notify observers about new message
            NotificationCenter.default.post(
                name: .newChatMessage,
                object: chatMessage
            )
            
            print("Received chat message from \(chatMessage.sender.displayName)")
        } catch {
            print("Failed to handle chat message: \(error)")
        }
    }
    
    private func handleRoomUpdate(_ wsMessage: WebSocketMessage) {
        // Handle room updates (participants joined/left, etc.)
        print("Room update received")
    }
    
    private func handleUserPresence(_ wsMessage: WebSocketMessage) {
        // Handle user presence updates
        print("User presence update received")
    }
    
    private func handlePong() {
        lastPongReceived = Date()
    }
    
    private func handleError(_ wsMessage: WebSocketMessage) {
        do {
            let errorInfo = try JSONDecoder().decode([String: String].self, from: wsMessage.payload)
            let error = WebSocketError.serverError(errorInfo["message"] ?? "Unknown error")
            lastError = error
            print("Server error: \(error)")
        } catch {
            print("Failed to decode error message: \(error)")
        }
    }
    
    // MARK: - Connection Health
    
    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sendPing()
            }
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() async {
        guard connectionState.isConnected else { return }
        
        let pingMessage = WebSocketMessage(type: .ping, payload: Data())
        do {
            try await sendMessage(pingMessage)
        } catch {
            print("Failed to send ping: \(error)")
        }
        
        // Check if we've received a pong recently
        if Date().timeIntervalSince(lastPongReceived) > pingInterval * 2 {
            print("Connection appears to be dead, reconnecting...")
            disconnect()
            await reconnectWithBackoff()
        }
    }
    
    // MARK: - Private Helpers
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    private func establishConnection() async throws {
        guard let serverURL = serverURL,
              let urlSession = urlSession else {
            throw WebSocketError.invalidURL
        }
        
        webSocketTask = urlSession.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        // Start listening for messages
        await startListening()
    }
    
    private func startListening() async {
        guard let webSocketTask = webSocketTask else { return }
        
        do {
            let message = try await webSocketTask.receive()
            
            switch message {
            case .data(let data):
                handleIncomingMessage(data)
            case .string(let string):
                if let data = string.data(using: .utf8) {
                    handleIncomingMessage(data)
                }
            @unknown default:
                print("Unknown WebSocket message type")
            }
            
            // Continue listening
            await startListening()
            
        } catch {
            print("WebSocket receive error: \(error)")
            if connectionState == .connected {
                await reconnectWithBackoff()
            }
        }
    }
    
    private func getCurrentUserId() -> String {
        // This would normally come from user authentication
        return "user-\(UUID().uuidString.prefix(8))"
    }
    
    deinit {
        // Can't call async methods in deinit, so just clean up synchronously
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        pingTimer?.invalidate()
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketManager: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            print("WebSocket connection opened")
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            print("WebSocket connection closed with code: \(closeCode)")
            if connectionState == .connected {
                await reconnectWithBackoff()
            }
        }
    }
}

// MARK: - Supporting Types

/// WebSocket-specific errors
enum WebSocketError: Error, LocalizedError {
    case notConnected
    case notInRoom
    case invalidURL
    case encryptionFailed
    case decryptionFailed
    case serverError(String)
    case connectionTimeout
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to WebSocket server"
        case .notInRoom:
            return "Not currently in a room"
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .encryptionFailed:
            return "Failed to encrypt message"
        case .decryptionFailed:
            return "Failed to decrypt message"
        case .serverError(let message):
            return "Server error: \(message)"
        case .connectionTimeout:
            return "Connection timeout"
        }
    }
}

/// Room join request
struct RoomJoinRequest: Codable {
    let roomId: UUID
    let userId: String
    let timestamp: Date
    
    init(roomId: UUID, userId: String) {
        self.roomId = roomId
        self.userId = userId
        self.timestamp = Date()
    }
}

/// Room leave request
struct RoomLeaveRequest: Codable {
    let roomId: UUID
    let userId: String
    let timestamp: Date
    
    init(roomId: UUID, userId: String) {
        self.roomId = roomId
        self.userId = userId
        self.timestamp = Date()
    }
}



// MARK: - Notifications

extension Notification.Name {
    static let newChatMessage = Notification.Name("newChatMessage")
    static let roomUpdate = Notification.Name("roomUpdate")
    static let userPresenceUpdate = Notification.Name("userPresenceUpdate")
    static let webSocketError = Notification.Name("webSocketError")
}