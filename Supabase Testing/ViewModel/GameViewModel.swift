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
    // MARK: - Constants
    private let lobbyChannelId = "tictactoe-lobby"
    
    // MARK: - Published Properties
    @Published var playerName: String
    @Published var connectionStatus: String = "Disconnected"
    @Published var isConnected = false
    @Published var onlinePlayers: Set<String> = []
    @Published var selectedPlayer: String?
    @Published var incomingInviteFrom: String?
    @Published var pendingInviteTo: String?
    @Published var activeGameRoomId: String?
    @Published var isHostForActiveGame: Bool? = nil
    @Published var opponentName: String? = nil
    @Published var systemMessage: String = "Connect and join lobby to invite a player."
    
    // MARK: - Private Properties
    private let realtimeClient: SupabaseRealtimeClient
    var realtime: SupabaseRealtimeClient { realtimeClient }
    // MARK: - Initialization
    init(
        playerName: String,
        realtimeClient: SupabaseRealtimeClient = SupabaseRealtimeClient(
            config: SupabaseRealtimeConfig(
                url: "https://eilxfocmlnzsjkrgbvvv.supabase.co",
                apiKey: "sb_publishable_PhNhE083zZ3FMjOBbsxeXw_wMT6k8-o"
            )
        )
    ) {
        self.playerName = playerName
        self.realtimeClient = realtimeClient
        self.realtimeClient.delegate = self
    }
    
    // MARK: - Public Methods
    func connect() {
        guard !playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            systemMessage = "Player name is required."
            return
        }
        
        realtimeClient.connect()
    }
    
    func disconnect() {
        if activeGameRoomId != nil {
            leaveGameRoom()
        }
        realtimeClient.leaveChannel(channelId: lobbyChannelId)
        realtimeClient.disconnect()
        resetLobbyState()
    }
    
    func joinLobby() {
        guard isConnected else {
            systemMessage = "Connect to realtime first."
            return
        }
        
        let cleanName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            systemMessage = "Player name is required."
            return
        }
        
        realtimeClient.joinChannel(channelId: lobbyChannelId, username: cleanName)
        systemMessage = "Joining lobby..."
    }
    
    func sendInvite() {
        guard let target = selectedPlayer, !target.isEmpty else {
            systemMessage = "Select a player to invite."
            return
        }
        
        guard target != playerName else {
            systemMessage = "You cannot invite yourself."
            return
        }
        
        pendingInviteTo = target
        opponentName = target
        systemMessage = "Invite sent to \(target)."
        
        realtimeClient.broadcast(
            channelId: lobbyChannelId,
            event: "match_invite",
            payload: [
                "from": playerName,
                "to": target,
                "sent_at": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }
    
    func acceptInvite() {
        guard let inviter = incomingInviteFrom else {
            return
        }
        
        isHostForActiveGame = false
        opponentName = inviter
        
        let gameRoomId = Self.makeGameRoomId(playerA: inviter, playerB: playerName)
        incomingInviteFrom = nil
        activeGameRoomId = gameRoomId
        
        realtimeClient.broadcast(
            channelId: lobbyChannelId,
            event: "match_invite_response",
            payload: [
                "from": playerName,
                "to": inviter,
                "accepted": true,
                "game_room_id": gameRoomId
            ]
        )
        
        moveToGameRoom(gameRoomId)
    }
    
    func rejectInvite() {
        guard let inviter = incomingInviteFrom else {
            return
        }
        
        incomingInviteFrom = nil
        realtimeClient.broadcast(
            channelId: lobbyChannelId,
            event: "match_invite_response",
            payload: [
                "from": playerName,
                "to": inviter,
                "accepted": false
            ]
        )
        systemMessage = "Invite rejected."
    }
    
    func leaveGameRoom() {
        guard let roomId = activeGameRoomId else {
            return
        }
        
        realtimeClient.leaveChannel(channelId: roomId)
        activeGameRoomId = nil
        realtimeClient.joinChannel(channelId: lobbyChannelId, username: playerName)
        systemMessage = "Returned to lobby."
    }
    
    private func moveToGameRoom(_ gameRoomId: String) {
        realtimeClient.leaveChannel(channelId: lobbyChannelId)
        realtimeClient.joinChannel(channelId: gameRoomId, username: playerName)
        systemMessage = "Entered game room \(gameRoomId)."
    }
    
    private func resetLobbyState() {
        onlinePlayers = []
        selectedPlayer = nil
        incomingInviteFrom = nil
        pendingInviteTo = nil
        activeGameRoomId = nil
        systemMessage = "Disconnected."
    }
    
    private static func makeGameRoomId(playerA: String, playerB: String) -> String {
        let names = [playerA.lowercased(), playerB.lowercased()].sorted()
        return "tictactoe-game-\(names.joined(separator: "-"))-\(Int(Date().timeIntervalSince1970))"
    }
    
    private func parseSocketMessage(_ message: [String: Any]) {
        guard let payload = message["payload"] as? [String: Any],
              let eventType = payload["event"] as? String,
              let payloadData = payload["payload"] as? [String: Any] else {
            return
        }
        
        switch eventType {
        case "match_invite":
            handleInvite(payloadData)
        case "match_invite_response":
            handleInviteResponse(payloadData)
        default:
            break
        }
    }
    
    private func handleInvite(_ payload: [String: Any]) {
        guard let to = payload["to"] as? String,
              let from = payload["from"] as? String,
              to == playerName,
              from != playerName else {
            return
        }
        
        incomingInviteFrom = from
        systemMessage = "\(from) invited you to play."
    }
    
    private func handleInviteResponse(_ payload: [String: Any]) {
        guard let to = payload["to"] as? String,
              let from = payload["from"] as? String,
              to == playerName else {
            return
        }
        
        let accepted = payload["accepted"] as? Bool ?? false
        if accepted {
            guard let roomId = payload["game_room_id"] as? String else {
                systemMessage = "\(from) accepted, but game room id is missing."
                return
            }
            activeGameRoomId = roomId
            pendingInviteTo = nil
            isHostForActiveGame = true
            opponentName = from
            moveToGameRoom(roomId)
        } else {
            pendingInviteTo = nil
            systemMessage = "\(from) rejected your invite."
        }
    }
}

extension GameViewModel: SupabaseRealtimeClientDelegate {
    func client(_ client: SupabaseRealtimeClient, didChangeState state: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = state == .connected
            self?.connectionStatus = state.description
            
            if state == .connected {
                self?.systemMessage = "Connected. Join lobby to view players."
            }
        }
    }
    
    func client(_ client: SupabaseRealtimeClient, channel: String, didReceivePresenceState users: [PresenceUser]) {
        guard channel == lobbyChannelId else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            
            let names = users.map(\.username).filter { $0 != self.playerName }.sorted()
            names.forEach({self.onlinePlayers.insert($0)})
            if let selectedPlayer, !names.contains(selectedPlayer) {
                self.selectedPlayer = nil
            }
        }
    }
    
    func client(_ client: SupabaseRealtimeClient, didReceivePresenceDiff diff: PresenceDiff) {
        guard diff.channelId == lobbyChannelId else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            
            let joinedUsers = diff.joins.map({$0.username})
                .filter { $0 != self.playerName }
                .sorted()
            joinedUsers.forEach({self.onlinePlayers.insert($0)})
            
            let leftUsers = diff.leaves.map({$0.username})
                .sorted()
            leftUsers.forEach({self.onlinePlayers.remove($0)})
            if let selectedPlayer, leftUsers.contains(selectedPlayer) {
                self.selectedPlayer = nil
            }
        }
    }
    
    func client(_ client: SupabaseRealtimeClient, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.parseSocketMessage(message)
        }
    }
    
    func client(_ client: SupabaseRealtimeClient, didFailWithError error: any Error) {
        DispatchQueue.main.async { [weak self] in
            self?.systemMessage = error.localizedDescription
        }
    }
}

