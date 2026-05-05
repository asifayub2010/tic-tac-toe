////
////  GameRoomManager.swift
////  Supabase Testing
////
////  Created by mac on 03/05/2026.
////
//
//
//import Foundation
//import Supabase
//import Combine
//
//// MARK: - Game Event Models
//
//struct GameEvent: Codable {
//    let type: String
//    let payload: [String: AnyJSON]
//}
//
//struct PlayerPresence: Codable {
//    let playerId: String
//    let displayName: String
//    let joinedAt: Date
//
//    enum CodingKeys: String, CodingKey {
//        case playerId    = "player_id"
//        case displayName = "display_name"
//        case joinedAt    = "joined_at"
//    }
//}
//
//// MARK: - GameRoomManager
//
//@MainActor
//final class GameRoomManager: ObservableObject {
//    let objectWillChange: ObservableObjectPublisher = ObservableObjectPublisher()
//    
//
//    // MARK: - Published State
//
//    @Published private(set) var isConnected = false
//    @Published private(set) var connectedPlayers: [PlayerPresence] = []
//
//    // MARK: - Private
//
//    private let supabase: SupabaseClient
//    private var channel: RealtimeChannelV2?
//    private var listenerTasks: [Task<Void, Never>] = []
//
//    // MARK: - Init
//
//    init(supabaseURL: String = "https://eilxfocmlnzsjkrgbvvv.supabase.co", supabaseKey: String = "sb_publishable_PhNhE083zZ3FMjOBbsxeXw_wMT6k8-o") {
//        self.supabase = SupabaseClient(
//            supabaseURL: URL(string: supabaseURL)!,
//            supabaseKey: supabaseKey
//        )
//    }
//
//    // MARK: - Room Management
//
//    /// Joins a game room channel and starts listening for events.
//    /// - Parameters:
//    ///   - roomId: Unique identifier for the game room (e.g. "room:abc123")
//    ///   - player: The local player's presence info to broadcast on join
//    func joinRoom(roomId: String, player: PlayerPresence) async {
//        // Clean up any existing room first
//        await leaveRoom()
//
//        let channelName = "realtime:public:test_\(roomId)"
//        let ch = supabase.channel(channelName)
//        self.channel = ch
//
//        // Register all listeners BEFORE subscribing (required by the SDK)
//        startListeningBroadcast(channel: ch)
//        startListeningPresence(channel: ch)
//
//        // Subscribe (opens the WebSocket connection)
//        do {
//            try await ch.subscribeWithError()
//            isConnected = true
//        } catch {
//            print("error in subscription: ", error.localizedDescription)
//        }
//
//        // Track the local player's presence in the room
//        do {
//            try await ch.track(player)
//        } catch {
//            print("[GameRoomManager] Failed to track presence: \(error)")
//        }
//    }
//
//    /// Leaves the current room and cleans up all resources.
//    func leaveRoom() async {
//        listenerTasks.forEach { $0.cancel() }
//        listenerTasks.removeAll()
//
//        if let ch = channel {
//            await supabase.removeChannel(ch)
//        }
//
//        channel = nil
//        isConnected = false
//        connectedPlayers = []
//    }
//
//    // MARK: - Sending Events
//
//    /// Broadcasts a game event to all players in the room.
//    func send(event: String, payload: [String: AnyJSON]) async {
//        guard let ch = channel else {
//            print("[GameRoomManager] Cannot send — not connected to a room.")
//            return
//        }
//        
//        await ch.broadcast(event: event, message: payload)
//    }
//
//    // MARK: - Private Listeners
//
//    private func startListeningBroadcast(channel ch: RealtimeChannelV2) {
//        // Listen for game events (e.g. "player_moved", "game_started")
//        let task = Task {
//            let stream = ch.broadcastStream(event: "game_event")
//            for await message in stream {
//                guard !Task.isCancelled else { break }
//                await handleGameEvent(message)
//            }
//        }
//        listenerTasks.append(task)
//    }
//
//    private func startListeningPresence(channel ch: RealtimeChannelV2) {
//        // Sync current presence state when first connecting
//        let syncTask = Task {
//            let stream = ch.presenceChange()
//            for await state in stream {
//                guard !Task.isCancelled else { break }
//                await updatePresence(from: state)
//            }
//        }
//        listenerTasks.append(syncTask)
//    }
//
//    // MARK: - Event Handlers
//
//    private func handleGameEvent(_ message: [String: AnyJSON]) async {
//        // Route game events by type — customise for your game
//        guard let eventType = message["type"]?.stringValue else { return }
//
//        switch eventType {
//        case "player_moved":
//            print("[GameRoomManager] Player moved: \(message)")
//        case "game_started":
//            print("[GameRoomManager] Game has started!")
//        case "game_ended":
//            print("[GameRoomManager] Game ended.")
//        default:
//            print("[GameRoomManager] Unknown event: \(eventType)")
//        }
//    }
//
//    private func updatePresence(from state: any PresenceAction) async {
//        print("join state: ", state.joins)
//        print("left state: ", state.leaves)
//        print("raw message: ", state.rawMessage)
////        do {
////            // Decode all currently tracked players from presence state
////            let players: [PlayerPresence] = try state.decodeAll()
////            self.connectedPlayers = players
////            print("[GameRoomManager] Players in room: \(players.count)")
////        } catch {
////            print("[GameRoomManager] Failed to decode presence: \(error)")
////        }
//    }
//}
