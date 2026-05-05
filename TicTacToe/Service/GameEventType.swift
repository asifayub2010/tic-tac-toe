import Foundation
import SwiftUI
import Combine
import Supabase

class SupabaseWebSocketService: ObservableObject {

    // MARK: - Published
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var playersInRoom: Set<String> = []
    @Published var opponentJoined = false

    // MARK: - Private
    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?

    private var roomId: String?
    private var playerId: String = UUID().uuidString

    // Turn logic
    private var turnTimeoutTimer: Timer?
    private var consecutiveMissedTurns = 0
    private var currentTurnPlayerId: String?
    private var gamePlayerMode: GamePlayerMode = .twoPlayer

    // MARK: - Init
    init() {
        client = SupabaseClient(
            supabaseURL: URL(string: "https://eilxfocmlnzsjkrgbvvv.supabase.co")!,
            supabaseKey: "sb_publishable_PhNhE083zZ3FMjOBbsxeXw_wMT6k8-o"
        )
    }

    // MARK: - ROOM

    func createRoom(gamePlayerMode: GamePlayerMode = .twoPlayer) async throws -> String {
        self.gamePlayerMode = gamePlayerMode
        roomId = generateRoomId()
        try await joinRoom()
        startTurnTimeoutTimer()
        return roomId!
    }

    func joinRoom(roomCode: String, gamePlayerMode: GamePlayerMode = .twoPlayer) async throws {
        self.gamePlayerMode = gamePlayerMode
        roomId = roomCode.uppercased()
        try await joinRoom()
    }

    private func joinRoom() async throws {
        guard let roomId else { return }

        let topic = "room_\(roomId)"

        // Create channel
        let channel = client.channel(topic)

        self.channel = channel

        // MARK: - Presence
        channel.onPresenceChange { [weak self] state in
            guard let self else { return }

            let players = Set(state.joins.keys)

            DispatchQueue.main.async {
                self.playersInRoom = players
                self.opponentJoined = players.count > 1
            }

            print("🟢 Presence:", players)
        }

        // MARK: - Broadcast
        channel.onBroadcast(event: "phx_join") { [weak self] message in
            guard let self else { return }

            print("📩 Broadcast:", message)

            if let payload = message as? [String: Any] {
                self.handleGameMessage(payload)
            }
        }

        // MARK: - Subscribe
        let status = try? await channel.subscribe()

        switch status {
        case .subscribed:
            print("✅ Joined:", topic)
            DispatchQueue.main.async {
                self.isConnected = true
                self.connectionError = nil
            }

            // Track presence
            await channel.track([
                "user_id": playerId
            ])

        case .error:
            print("❌ Join error")
            DispatchQueue.main.async {
                self.connectionError = "Join failed"
            }

        case .timedOut:
            print("⏳ Join timeout")
            DispatchQueue.main.async {
                self.connectionError = "Join timeout"
            }

        default:
            break
        }
    }

    // MARK: - SEND

    func sendMove(row: Int, col: Int, player: String) async {
        guard let channel else { return }

        consecutiveMissedTurns = 0
        resetTurnTimeoutTimer()

        let message = GameMessage(
            type: .move,
            roomId: roomId ?? "",
            playerId: playerId,
            data: [
                "row": "\(row)",
                "col": "\(col)",
                "player": player,
                "playerId": playerId
            ],
            timestamp: Date()
        )

        await send(message)
    }

    func sendRematchRequest() async {
        guard let roomId else { return }

        let message = GameMessage(
            type: .rematch,
            roomId: roomId,
            playerId: playerId,
            data: ["requestId": UUID().uuidString],
            timestamp: Date()
        )

        await send(message)
    }

    func sendPlayerTimeout(playerId: String) async {
        guard let roomId else { return }

        let message = GameMessage(
            type: .playerTimeout,
            roomId: roomId,
            playerId: playerId,
            data: ["timeoutPlayer": playerId],
            timestamp: Date()
        )

        await send(message)
    }

    private func send(_ message: GameMessage) async {
        guard let channel else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(message),
              let payload = try? JSONSerialization.jsonObject(with: data) else {
            return
        }

        await channel.sendBroadcast(
            event: message.type.rawValue,
            payload: payload
        )
    }

    // MARK: - RECEIVE

    private func handleGameMessage(_ payload: [String: Any]) {
        guard let typeString = payload["type"] as? String,
              let type = GameEventType(rawValue: typeString),
              let roomId = payload["roomId"] as? String,
              let playerId = payload["playerId"] as? String else {
            return
        }

        guard playerId != self.playerId else { return }

        let data = payload["data"] as? [String: String] ?? [:]

        let message = GameMessage(
            type: type,
            roomId: roomId,
            playerId: playerId,
            data: data,
            timestamp: Date()
        )

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .gameEventReceived,
                object: nil,
                userInfo: ["message": message]
            )
        }
    }

    // MARK: - LEAVE

    func leaveRoom() async {
        stopTurnTimeoutTimer()
        await channel?.unsubscribe()
        channel = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.playersInRoom.removeAll()
            self.opponentJoined = false
        }
    }

    // MARK: - TURN LOGIC (same as yours)

    private func startTurnTimeoutTimer() {
        stopTurnTimeoutTimer()

        turnTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { await self?.handleTurnTimeout() }
        }
    }

    private func resetTurnTimeoutTimer() {
        if currentTurnPlayerId == playerId {
            startTurnTimeoutTimer()
        }
    }

    private func stopTurnTimeoutTimer() {
        turnTimeoutTimer?.invalidate()
        turnTimeoutTimer = nil
    }

    private func handleTurnTimeout() async {
        consecutiveMissedTurns += 1

        if gamePlayerMode == .twoPlayer {
            if consecutiveMissedTurns >= 2 {
                await sendPlayerTimeout(playerId: currentTurnPlayerId ?? "")
            } else {
                await sendRandomMove()
            }
        } else {
            await sendRandomMove()
            if currentTurnPlayerId == playerId {
                startTurnTimeoutTimer()
            }
        }
    }

    private func sendRandomMove() async {
        let row = Int.random(in: 0..<9)
        let col = Int.random(in: 0..<9)
        await sendMove(row: row, col: col, player: currentTurnPlayerId ?? "")
    }

    // MARK: - Helpers

    private func generateRoomId() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in letters.randomElement()! })
    }
}









//// Services/SupabaseWebSocketService.swift
//
//import Foundation
//import SwiftUI
//import Combine
//import SwiftPhoenixClient

enum GameEventType: String, Codable {
    case move = "move"
    case rematch = "rematch"
    case leave = "leave"
    case sync = "sync"
    case startGame = "start_game"
    case playerTimeout = "player_timeout"
}

struct GameMessage: Codable {
    let type: GameEventType
    let roomId: String
    let playerId: String
    let data: [String: String]
    let timestamp: Date
}

enum GamePlayerMode: String {
    case twoPlayer = "two_player"
    case threePlayer = "three_player"
}

//class SupabaseWebSocketService: NSObject, ObservableObject {
//
//    // MARK: - Published Properties
//    @Published var isConnected = false
//    @Published var connectionError: String?
//    @Published var playersInRoom: Set<String> = []
//    @Published var opponentJoined = false
//    @Published var currentPlayerId: String?
//
//    // MARK: - Private Properties
//    private var socket: Socket?
//    private var channel: Channel?
//    private var presence: Presence?
//
//    private var roomId: String?
//    private var playerId: String = ""
//    private var isHost: Bool = false
//
//    private var reconnectAttempts = 0
//    private let maxReconnectAttempts = 5
//
//    // Turn timeout
//    private var turnTimeoutTimer: Timer?
//    private var consecutiveMissedTurns: Int = 0
//    private var currentTurnPlayerId: String?
//    private var gamePlayerMode: GamePlayerMode = .twoPlayer
//
//    // Supabase Config
//    private let supabaseUrl: String
//    private let supabaseKey: String
//
//    // MARK: - Init
//    init(
//        supabaseUrl: String = "eilxfocmlnzsjkrgbvvv.supabase.co",
//        supabaseKey: String = "sb_publishable_PhNhE083zZ3FMjOBbsxeXw_wMT6k8-o"
//    ) {
//        self.supabaseUrl = supabaseUrl.replacingOccurrences(of: "https://", with: "")
//        self.supabaseKey = supabaseKey
//        super.init()
//        self.playerId = getDeviceId()
//        setupSocket()
//    }
//
//    // MARK: - Socket Setup
//    private func setupSocket() {
//        let url = "wss://\(supabaseUrl)/realtime/v1"
//
//        socket = Socket(url, params: [
//            "apikey": supabaseKey,
//            "vsn": "1.0.0"
//        ])
//        
//        socket?.logger = { msg in print("LOG:", msg) }
//
//        socket?.onOpen { [weak self] in
//            print("✅ Socket opened")
//            DispatchQueue.main.async {
//                self?.isConnected = true
//                self?.connectionError = nil
//            }
//        }
//
//        socket?.onClose { [weak self] in
//            print("❌ Socket closed")
//            DispatchQueue.main.async {
//                self?.isConnected = false
//            }
//            self?.attemptReconnect()
//        }
//
//        socket?.onError { [weak self] error in
//            print("❌ Socket error:", error)
//            DispatchQueue.main.async {
//                self?.connectionError = "Socket error"
//                self?.isConnected = false
//            }
//        }
//    }
//
//    // MARK: - Public API
//
//    func createRoom(gamePlayerMode: GamePlayerMode = .twoPlayer) async throws -> String {
//        self.gamePlayerMode = gamePlayerMode
//        roomId = generateRoomId()
//        isHost = true
//        try await connect()
//        await joinRoom()
//        startTurnTimeoutTimer()
//        return roomId!
//    }
//
//    func joinRoom(roomCode: String, gamePlayerMode: GamePlayerMode = .twoPlayer) async throws {
//        self.gamePlayerMode = gamePlayerMode
//        roomId = roomCode.uppercased()
//        isHost = false
//        try await connect()
//        await joinRoom()
//    }
//
//    func sendMove(row: Int, col: Int, player: String) async {
//        guard let channel = channel, let roomId = roomId else { return }
//
//        consecutiveMissedTurns = 0
//        resetTurnTimeoutTimer()
//
//        let message = GameMessage(
//            type: .move,
//            roomId: roomId,
//            playerId: playerId,
//            data: [
//                "row": String(row),
//                "col": String(col),
//                "player": player,
//                "playerId": playerId
//            ],
//            timestamp: Date()
//        )
//
//        sendBroadcast(message)
//    }
//
//    func sendRematchRequest() async {
//        guard let roomId = roomId else { return }
//
//        let message = GameMessage(
//            type: .rematch,
//            roomId: roomId,
//            playerId: playerId,
//            data: ["requestId": UUID().uuidString],
//            timestamp: Date()
//        )
//
//        sendBroadcast(message)
//    }
//
//    func sendPlayerTimeout(playerId: String) async {
//        guard let roomId = roomId else { return }
//
//        let message = GameMessage(
//            type: .playerTimeout,
//            roomId: roomId,
//            playerId: playerId,
//            data: ["timeoutPlayer": playerId],
//            timestamp: Date()
//        )
//
//        sendBroadcast(message)
//    }
//
//    func leaveRoom() async {
//        stopTurnTimeoutTimer()
//        channel?.leave()
//        disconnect()
//    }
//
//    func setCurrentTurnPlayer(playerId: String) {
//        currentTurnPlayerId = playerId
//        if playerId == self.playerId {
//            startTurnTimeoutTimer()
//        } else {
//            stopTurnTimeoutTimer()
//        }
//    }
//
//    // MARK: - Connection
//
//    func connect() async throws {
//        guard let socket = socket, !socket.isConnected else { return }
//        socket.connect()
//        try await Task.sleep(nanoseconds: 1_000_000_000)
//
//        if socket.isConnected != true {
//            throw WebSocketError.connectionFailed("Socket not connected")
//        }
//    }
//
//    private func joinRoom() async {
//        guard let roomId = roomId else { return }
//
//        let topic = "realtime:public:room_\(roomId)"
//
//        // Create channel
//        channel = socket?.channel(topic, params: [
//            "event": "phx_join",
//            "config": [
//                "broadcast": [
//                    "ack": true,
//                    "self": true
//                ],
//                "presence": [
//                    "enabled": true,
//                    "key": playerId
//                ]
//            ]
//        ])
//
//        guard let channel = channel else { return }
//
//        // MARK: - Broadcast Listener
//        channel.on("broadcast") { [weak self] msg in
//            guard let payload = msg.payload["payload"] as? [String: Any] else { return }
//            self?.handleGameMessage(payload)
//        }
//
//        // MARK: - Presence Setup (5.3.5 compatible)
//        presence = Presence(channel: channel)
//
//        // Initial + full sync
//        presence?.onSync { [weak self] in
//            guard let self = self,
//                  let presence = self.presence else { return }
//
//            let players = Set(presence.state.keys)
//
//            DispatchQueue.main.async {
//                self.playersInRoom = players
//                self.opponentJoined = players.count > 1
//            }
//
//            print("🟢 Presence sync:", players)
//        }
//
//        // Player joined
//        presence?.onJoin { key, current, new in
//            print("➕ Player joined:", key)
//        }
//
//        // Player left
//        presence?.onLeave { key, current, left in
//            print("➖ Player left:", key)
//        }
//
//        // MARK: - Join Channel
//        await withCheckedContinuation { continuation in
//            channel.join()
//                .receive("ok") { _ in
//                    print("✅ Joined channel:", topic)
//                    continuation.resume()
//                }
//                .receive("error") { payload in
//                    print("❌ Join failed:", payload)
//                    DispatchQueue.main.async {
//                        self.connectionError = "Failed to join room"
//                    }
//                    continuation.resume()
//                }
//        }
//    }
//
//    // MARK: - Messaging
//
//    private func sendBroadcast(_ message: GameMessage) {
//        guard let channel = channel else { return }
//
//        let encoder = JSONEncoder()
//        encoder.dateEncodingStrategy = .iso8601
//
//        guard let data = try? encoder.encode(message),
//              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
//            return
//        }
//
//        channel.push("broadcast", payload: [
//            "event": message.type.rawValue,
//            "payload": payload
//        ])
//    }
//
//    private func handleGameMessage(_ payload: [String: Any]) {
//        guard let typeString = payload["type"] as? String,
//              let type = GameEventType(rawValue: typeString),
//              let roomId = payload["roomId"] as? String,
//              let playerId = payload["playerId"] as? String else {
//            return
//        }
//
//        guard playerId != self.playerId else { return }
//
//        let data = payload["data"] as? [String: String] ?? [:]
//
//        let message = GameMessage(
//            type: type,
//            roomId: roomId,
//            playerId: playerId,
//            data: data,
//            timestamp: Date()
//        )
//
//        DispatchQueue.main.async {
//            NotificationCenter.default.post(
//                name: .gameEventReceived,
//                object: nil,
//                userInfo: ["message": message]
//            )
//        }
//    }
//
//    // MARK: - Turn Logic
//
//    private func startTurnTimeoutTimer() {
//        stopTurnTimeoutTimer()
//
//        turnTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
//            Task { await self?.handleTurnTimeout() }
//        }
//    }
//
//    private func resetTurnTimeoutTimer() {
//        if currentTurnPlayerId == playerId {
//            startTurnTimeoutTimer()
//        }
//    }
//
//    private func stopTurnTimeoutTimer() {
//        turnTimeoutTimer?.invalidate()
//        turnTimeoutTimer = nil
//    }
//
//    private func handleTurnTimeout() async {
//        consecutiveMissedTurns += 1
//
//        if gamePlayerMode == .twoPlayer {
//            if consecutiveMissedTurns >= 2 {
//                await sendPlayerTimeout(playerId: currentTurnPlayerId ?? "")
//            } else {
//                await sendRandomMove()
//            }
//        } else {
//            await sendRandomMove()
//            if currentTurnPlayerId == playerId {
//                startTurnTimeoutTimer()
//            }
//        }
//    }
//
//    private func sendRandomMove() async {
//        let row = Int.random(in: 0..<9)
//        let col = Int.random(in: 0..<9)
//        await sendMove(row: row, col: col, player: currentTurnPlayerId ?? "")
//    }
//
//    // MARK: - Reconnect
//
//    private func attemptReconnect() {
//        guard reconnectAttempts < maxReconnectAttempts else { return }
//
//        reconnectAttempts += 1
//        let delay = Double(reconnectAttempts) * 2
//
//        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
//            Task { await self?.reconnect() }
//        }
//    }
//
//    private func reconnect() async {
//        disconnect()
//
//        do {
//            try await connect()
//            await joinRoom()
//            reconnectAttempts = 0
//        } catch {
//            attemptReconnect()
//        }
//    }
//
//    func disconnect() {
//        channel?.leave()
//        channel = nil
//        socket?.disconnect()
//
//        DispatchQueue.main.async {
//            self.isConnected = false
//            self.playersInRoom.removeAll()
//            self.opponentJoined = false
//        }
//    }
//
//    // MARK: - Helpers
//
//    private func generateRoomId() -> String {
//        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789"
//        return String((0..<6).map { _ in letters.randomElement()! })
//    }
//
//    private func getDeviceId() -> String {
//        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
//    }
//}
//
//// MARK: - Errors
//
//enum WebSocketError: Error {
//    case connectionTimeout
//    case connectionFailed(String)
//}
//
//// MARK: - Notifications
//
//extension Notification.Name {
//    static let gameEventReceived = Notification.Name("gameEventReceived")
//}
//
