//
//  GameViewModel.swift
//  Supabase Testing
//
//  Created by mac on 02/05/2026.
//


// ViewModels/GameViewModel.swift

import Foundation
import SwiftUI
import Combine

class GameViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var playerName: String = ""
    @Published var roomId: String = ""
    @Published var isInRoom: Bool = false
    @Published var messageText: String = ""
    @Published var messages: [String] = []
    @Published var connectionStatus: String = "Disconnected"
    @Published var isConnected = false
    @Published var users: [String] = []
    
    // MARK: - Private Properties
    private let realtimeClient: SupabaseRealtimeClient
    private var cancellables = Set<AnyCancellable>()
//    private let starscreamClient: SupabaseRealtimeSocketManager
    
    // MARK: - Initialization
    init(realtimeClient: SupabaseRealtimeClient = SupabaseRealtimeClient(config: SupabaseRealtimeConfig(url: "https://eilxfocmlnzsjkrgbvvv.supabase.co", apiKey: "sb_publishable_PhNhE083zZ3FMjOBbsxeXw_wMT6k8-o"))) {
        self.realtimeClient = realtimeClient
//        starscreamClient = SupabaseRealtimeSocketManager()
    }
    
    // MARK: - Public Methods
    func connect() {
        if realtimeClient.delegate is Self == false {
            realtimeClient.delegate = self
        }
        realtimeClient.connect()
//        starscreamClient.connect()
    }
    
    func disconnect() {
        realtimeClient.disconnect()
        isInRoom = false
        roomId = ""
    }
    
    func joinRoom(playerName: String) {
        realtimeClient.joinChannel(channelId: "1234", username: playerName)
        self.playerName = playerName
    }
    
    func leaveRoom() {
        realtimeClient.leaveChannel(channelId: "1234")
    }
    
    func sendMessage(x: String, y: String) {
        realtimeClient.broadcastMove(channelId: "1234", player: playerName, x: x, y: y)
    }
}

extension GameViewModel: SupabaseRealtimeClientDelegate {
    func client(_ client: SupabaseRealtimeClient, didChangeState state: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = state == .connected
            self?.connectionStatus = state.description
        }
        
    }
    
    func client(_ client: SupabaseRealtimeClient, channel: String, didReceivePresenceState users: [PresenceUser]) {
        self.users = users.map({$0.username})
    }
    
    func client(_ client: SupabaseRealtimeClient, didReceivePresenceDiff diff: PresenceDiff) {
        self.users = diff.joins.map({$0.username})
    }
    
    func client(_ client: SupabaseRealtimeClient, didReceiveMessage message: [String : Any]) {
        messageText = message.map({"\($0.key): \($0.value)"}).joined()
    }
    
    func client(_ client: SupabaseRealtimeClient, didFailWithError error: any Error) {
        print(error.localizedDescription)
    }
    
    
}
