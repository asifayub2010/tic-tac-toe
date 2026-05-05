////
////  RealtimeClient.swift
////  Supabase Testing
////
////  Created by mac on 02/05/2026.
////
//
//
//// Services/RealtimeClient.swift
//
//import Foundation
//import Combine
//import Supabase
//import Realtime
//
//@MainActor
//class RealtimeClient: ObservableObject {
//    // MARK: - Published Properties
//    @Published var isConnected = false
//    @Published var lastMessage: String = ""
//    @Published var errorMessage: String?
//    @Published var playersInRoom: Set<String> = []
//    
//    // MARK: - Private Properties
//    private let supabase: SupabaseClient
//    private var channel: RealtimeChannelV2?
//    private var currentRoomId: String?
//    private var currentPlayerName: String = ""
//    private var messageTask: Task<Void, Never>?
//    private var presenceTask: Task<Void, Never>?
//    
//    // MARK: - Initialization
//    init(supabaseURL: String = "https://eilxfocmlnzsjkrgbvvv.supabase.co",
//         supabaseKey: String = "sb_publishable_PhNhE083zZ3FMjOBbsxeXw_wMT6k8-o") {
//        
//        self.supabase = SupabaseClient(
//            supabaseURL: URL(string: supabaseURL)!,
//            supabaseKey: supabaseKey
//        )
//        
//        setupRealtime()
//    }
//    
//    private func setupRealtime() {
//        // Monitor connection status
//        Task {
//            for await status in supabase.realtimeV2.statusChange {
//                await MainActor.run {
//                    switch status {
//                    case .connected:
//                        self.isConnected = true
//                        self.errorMessage = nil
//                        print("✅ Realtime connected")
//                    case .connecting:
//                        print("🔄 Realtime connecting...")
//                    case .disconnected:
//                        self.isConnected = false
//                        print("❌ Realtime disconnected")
//                    @unknown default:
//                        print("default connection status: ", status.description)
//                        break
//                    }
//                }
//            }
//        }
//    }
//    
//    // MARK: - Public Methods
//    func connect() async {
//        // Supabase SDK connects automatically when channel is subscribed
//        await supabase.realtimeV2.connect()
//        print("✅ Realtime client ready")
//    }
//    
//    func disconnect() async {
//        await leaveRoom()
//        messageTask?.cancel()
//        presenceTask?.cancel()
//        messageTask = nil
//        presenceTask = nil
//        print("❌ Realtime disconnected")
//    }
//    
//    func joinRoom(roomId: String, playerName: String) async {
//        self.currentRoomId = roomId
//        self.currentPlayerName = playerName
//        
//        // Leave existing channel if any
//        await leaveRoom()
//        
//        // Create new channel
//        let topic = "game:\(roomId)"
//        channel = supabase.realtimeV2.channel(topic)
//        
//        guard let channel = channel else { return }
//        
//        // 1. Setup Broadcast Listener (for chat messages)
//        let broadcastStream = channel.broadcastStream(event: "game_message")
////            .broadcast(
////            event: "game_message",
////            type: .broadcast
////        )
//        
//        messageTask = Task { [weak self] in
//            for await message in broadcastStream {
//                self?.handleBroadcastMessage(message)
//            }
//        }
//        
//        // 2. Setup Presence Tracking (for players in room)
//        presenceTask = Task { [weak self] in
//            for await presence in channel.presenceChange() {
//                self?.handlePresenceUpdate(presence)
//            }
//        }
//        
//        // 3. Subscribe to channel
//        Task { [weak self] in
//            do {
//                let status: () = try await channel.subscribeWithError()
//                await MainActor.run {
//                    self?.isConnected = true
//                    self?.lastMessage = "Joined room: \(roomId)"
//                }
//                print("✅ Subscribed to channel: \(topic)")
//                
//                // Track this player's presence
//                try await channel.track(["name": playerName])
//                print("✅ Tracked presence for: \(playerName)")
//                
//            } catch {
//                await MainActor.run {
//                    self?.errorMessage = "Failed to join room: \(error.localizedDescription)"
//                    self?.lastMessage = "Failed to join room"
//                }
//                print("❌ Failed to subscribe: \(error)")
//            }
//        }
//    }
//    
//    func leaveRoom() async {
//        guard let channel = channel else { return }
//        
//        Task {
//                await channel.untrack()
//                await channel.unsubscribe()
//                await MainActor.run {
//                    self.currentRoomId = nil
//                    self.lastMessage = "Left room"
//                    self.playersInRoom.removeAll()
//                }
//                print("✅ Left room")
//        }
//        
//        await channel.unsubscribe()
//        messageTask?.cancel()
//        presenceTask?.cancel()
//        messageTask = nil
//        presenceTask = nil
////        channel = nil
//    }
//    
//    func sendMessage(_ text: String) {
//        guard let channel = channel, let roomId = currentRoomId else {
//            Task { @MainActor in
//                self.errorMessage = "Not connected to any room"
//            }
//            return
//        }
//        
//        let payload: [String: AnyJSON] = [
//            "text": .string(text),
//            "sender": .string(currentPlayerName),
//            "roomId": .string(roomId),
//            "timestamp": .string(ISO8601DateFormatter().string(from: Date()))
//        ]
//        
//        Task {
//            await channel.broadcast(
//                event: "game_message",
//                message: payload
//            )
//            await MainActor.run {
//                self.lastMessage = "Me: \(text)"
//            }
//            print("✅ Message sent")
//        }
//    }
//    
//    // MARK: - Private Handlers
//    @MainActor
//    private func handleBroadcastMessage(_ message: JSONObject) {
//        let payload = message
//        let text = payload["text"]?.stringValue
//        let sender = payload["sender"]?.stringValue
//        
//        // Don't show our own messages (already shown when sent)
//        if sender != currentPlayerName {
//            self.lastMessage = "\(sender): \(text)"
//        }
//    }
//    
//    @MainActor
//    private func handlePresenceUpdate(_ presence: PresenceAction) {
//        print("joined players: ", presence.joins)
//        print("leaved players: ", presence.leaves)
//        // Extract player IDs from presence state
////        var players = Set<String>()
//        
////        for (key, value) in presence.joins {
////            // The key is the client ID, we can use it as player identifier
////            if let metas = value as? [[String: Any]],
////               let name = metas.first?["name"] as? String {
////                players.insert(name)
////            } else {
////                players.insert(key)
////            }
////        }
////        
////        self.playersInRoom = players
////        
////        // Notify about join/leave events
////        if players.contains(currentPlayerName) && players.count > 1 {
////            let others = players.filter { $0 != currentPlayerName }
////            self.lastMessage = "👤 Players in room: \(others.joined(separator: ", "))"
////        }
//    }
//}
