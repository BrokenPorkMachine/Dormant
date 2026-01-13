import Testing
import Foundation
@testable import DormantChat

@Suite("WebSocket Manager")
struct WebSocketManagerTests {
    
    @Test("WebSocket manager initializes with correct state")
    @MainActor
    func testInitialization() async throws {
        let manager = WebSocketManager()
        
        #expect(manager.connectionState == .disconnected)
        #expect(manager.currentRoom == nil)
        #expect(manager.lastError == nil)
    }
    
    @Test("Connection state transitions")
    @MainActor
    func testConnectionStateTransitions() async throws {
        let manager = WebSocketManager()
        
        // Initial state
        #expect(manager.connectionState == .disconnected)
        #expect(!manager.connectionState.isConnected)
        
        // Test state properties
        let connectedState = ConnectionState.connected
        #expect(connectedState.isConnected)
        #expect(connectedState.displayName == "Connected")
        
        let disconnectedState = ConnectionState.disconnected
        #expect(!disconnectedState.isConnected)
        #expect(disconnectedState.displayName == "Disconnected")
        
        let connectingState = ConnectionState.connecting
        #expect(!connectingState.isConnected)
        #expect(connectingState.displayName == "Connecting")
        
        let reconnectingState = ConnectionState.reconnecting
        #expect(!reconnectingState.isConnected)
        #expect(reconnectingState.displayName == "Reconnecting")
        
        let failedState = ConnectionState.failed
        #expect(!failedState.isConnected)
        #expect(failedState.displayName == "Connection Failed")
    }
    
    @Test("WebSocket message creation")
    func testWebSocketMessageCreation() async throws {
        let testData = "test message".data(using: .utf8)!
        let roomId = UUID()
        
        let message = WebSocketMessage(
            type: .chatMessage,
            roomId: roomId,
            payload: testData
        )
        
        #expect(message.type == .chatMessage)
        #expect(message.roomId == roomId)
        #expect(message.payload == testData)
        #expect(message.messageId != UUID()) // Should have a valid UUID
    }
    
    @Test("WebSocket message encoding and decoding")
    func testWebSocketMessageCodable() async throws {
        let testData = "test message".data(using: .utf8)!
        let roomId = UUID()
        
        let originalMessage = WebSocketMessage(
            type: .chatMessage,
            roomId: roomId,
            payload: testData
        )
        
        // Encode
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(originalMessage)
        
        // Decode
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(WebSocketMessage.self, from: encodedData)
        
        #expect(decodedMessage.type == originalMessage.type)
        #expect(decodedMessage.roomId == originalMessage.roomId)
        #expect(decodedMessage.payload == originalMessage.payload)
        #expect(decodedMessage.messageId == originalMessage.messageId)
    }
    
    @Test("Room join request creation")
    func testRoomJoinRequest() async throws {
        let roomId = UUID()
        let userId = "test-user"
        
        let request = RoomJoinRequest(roomId: roomId, userId: userId)
        
        #expect(request.roomId == roomId)
        #expect(request.userId == userId)
        #expect(request.timestamp <= Date()) // Should be recent
    }
    
    @Test("Room leave request creation")
    func testRoomLeaveRequest() async throws {
        let roomId = UUID()
        let userId = "test-user"
        
        let request = RoomLeaveRequest(roomId: roomId, userId: userId)
        
        #expect(request.roomId == roomId)
        #expect(request.userId == userId)
        #expect(request.timestamp <= Date()) // Should be recent
    }
    
    @Test("Room join and leave request encoding")
    func testRoomRequestsCodable() async throws {
        let roomId = UUID()
        let userId = "test-user"
        
        // Test join request
        let joinRequest = RoomJoinRequest(roomId: roomId, userId: userId)
        let joinData = try JSONEncoder().encode(joinRequest)
        let decodedJoinRequest = try JSONDecoder().decode(RoomJoinRequest.self, from: joinData)
        
        #expect(decodedJoinRequest.roomId == joinRequest.roomId)
        #expect(decodedJoinRequest.userId == joinRequest.userId)
        
        // Test leave request
        let leaveRequest = RoomLeaveRequest(roomId: roomId, userId: userId)
        let leaveData = try JSONEncoder().encode(leaveRequest)
        let decodedLeaveRequest = try JSONDecoder().decode(RoomLeaveRequest.self, from: leaveData)
        
        #expect(decodedLeaveRequest.roomId == leaveRequest.roomId)
        #expect(decodedLeaveRequest.userId == leaveRequest.userId)
    }
    
    @Test("WebSocket error descriptions")
    func testWebSocketErrors() async throws {
        let errors: [WebSocketError] = [
            .notConnected,
            .notInRoom,
            .invalidURL,
            .encryptionFailed,
            .decryptionFailed,
            .serverError("Test error"),
            .connectionTimeout
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
        
        // Test specific error message
        let serverError = WebSocketError.serverError("Custom error message")
        #expect(serverError.errorDescription?.contains("Custom error message") == true)
    }
    
    @Test("E2E encryption manager")
    func testE2EEncryptionManager() async throws {
        let manager = E2EEncryptionManager()
        let testMessage = ChatMessage(
            content: "Hello, this is a test message!",
            sender: .human(userId: "test", username: "Test User"),
            roomId: UUID()
        )
        
        // Test encryption and decryption
        let encrypted = try manager.encryptMessage(testMessage)
        let decrypted = try manager.decryptMessage(encrypted)
        
        #expect(decrypted.content == testMessage.content)
        #expect(decrypted.sender == testMessage.sender)
        #expect(decrypted.roomId == testMessage.roomId)
        
        // Test key data access
        let keyData = manager.getRoomKeyData()
        #expect(keyData.count == 32) // 256-bit key
    }
    
    @Test("WebSocket message types")
    func testWebSocketMessageTypes() async throws {
        let messageTypes: [WebSocketMessageType] = [
            .chatMessage,
            .joinRoom,
            .leaveRoom,
            .roomUpdate,
            .userPresence,
            .error,
            .ping,
            .pong
        ]
        
        // Test that all message types have valid raw values
        for messageType in messageTypes {
            #expect(!messageType.rawValue.isEmpty)
        }
        
        // Test specific raw values
        #expect(WebSocketMessageType.chatMessage.rawValue == "chat_message")
        #expect(WebSocketMessageType.joinRoom.rawValue == "join_room")
        #expect(WebSocketMessageType.leaveRoom.rawValue == "leave_room")
        #expect(WebSocketMessageType.roomUpdate.rawValue == "room_update")
        #expect(WebSocketMessageType.userPresence.rawValue == "user_presence")
        #expect(WebSocketMessageType.error.rawValue == "error")
        #expect(WebSocketMessageType.ping.rawValue == "ping")
        #expect(WebSocketMessageType.pong.rawValue == "pong")
    }
    
    @Test("Connection state all cases")
    func testConnectionStateAllCases() async throws {
        let allStates = ConnectionState.allCases
        
        #expect(allStates.count == 5)
        #expect(allStates.contains(.disconnected))
        #expect(allStates.contains(.connecting))
        #expect(allStates.contains(.connected))
        #expect(allStates.contains(.reconnecting))
        #expect(allStates.contains(.failed))
    }
    
    @Test("WebSocket manager disconnect")
    @MainActor
    func testDisconnect() async throws {
        let manager = WebSocketManager()
        
        // Should be able to disconnect even when not connected
        manager.disconnect()
        #expect(manager.connectionState == .disconnected)
        #expect(manager.currentRoom == nil)
    }
    
    @Test("WebSocket manager error handling for not connected")
    @MainActor
    func testErrorHandlingNotConnected() async throws {
        let manager = WebSocketManager()
        
        // Test sending message when not connected should throw
        let testMessage = ChatMessage(
            content: "test",
            sender: .human(userId: "user1", username: "Test User"),
            roomId: UUID()
        )
        
        do {
            try await manager.sendMessage(testMessage)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as WebSocketError {
            #expect(error == .notInRoom) // Should fail because not in room
        } catch {
            #expect(Bool(false), "Should have thrown WebSocketError")
        }
    }
    
    @Test("WebSocket manager error handling for not in room")
    @MainActor
    func testErrorHandlingNotInRoom() async throws {
        let manager = WebSocketManager()
        
        // Test leaving room when not in room should throw
        do {
            try await manager.leaveRoom()
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as WebSocketError {
            #expect(error == .notInRoom)
        } catch {
            #expect(Bool(false), "Should have thrown WebSocketError")
        }
    }
}

// MARK: - Helper Extensions for Testing

extension WebSocketError: Equatable {
    public static func == (lhs: WebSocketError, rhs: WebSocketError) -> Bool {
        switch (lhs, rhs) {
        case (.notConnected, .notConnected),
             (.notInRoom, .notInRoom),
             (.invalidURL, .invalidURL),
             (.encryptionFailed, .encryptionFailed),
             (.decryptionFailed, .decryptionFailed),
             (.connectionTimeout, .connectionTimeout):
            return true
        case (.serverError(let lhsMessage), .serverError(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}